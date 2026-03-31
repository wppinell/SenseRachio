import SwiftUI

// MARK: - ZoneCardView (Grid card design)

struct ZoneCardView: View {
    let zone: RachioZone
    let device: RachioDevice?
    let moisture: Double?
    let isActive: Bool
    let onStart: (Int) -> Void
    let onStop: () -> Void

    @State private var showDurationSheet = false
    @State private var selectedDuration = 10
    @State private var pulse = false

    @AppStorage(AppStorageKey.autoWaterThreshold) private var autoWaterThreshold: Double = 20
    @AppStorage(AppStorageKey.dryThreshold) private var dryThreshold: Double = 25
    @AppStorage(AppStorageKey.lowThreshold) private var highThreshold: Double = 40

    private let durations = [5, 10, 15, 20, 30]

    // MARK: - Computed

    private var hasMoisture: Bool { moisture != nil }

    private var moistureColor: Color {
        guard let m = moisture else { return DS.Color.textTertiary }
        if m < autoWaterThreshold { return DS.Color.error }
        if m < dryThreshold       { return DS.Color.warning }
        if m < highThreshold      { return DS.Color.online }
        return DS.Color.accent
    }

    private var weeklyMinutes: Int {
        guard let device else { return 0 }
        let schedules = device.schedules(forZoneId: zone.id)
        return Int(schedules.reduce(0.0) { $0 + (Double($1.duration) / 60.0 * $1.rule.runsPerWeekDouble) }.rounded())
    }

    private var weeklyRuntimeText: String {
        return Self.formatMins(weeklyMinutes)
    }

    static func formatMins(_ mins: Int) -> String {
        if mins == 0 { return "0m" }
        if mins < 60 { return "\(mins)m" }
        let hours = Double(mins) / 60.0
        return String(format: hours.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fh" : "%.1fh", hours)
    }

    private var weeklyFraction: Double {
        // Max ~10h/week = 600 mins
        return min(Double(weeklyMinutes) / 600.0, 1.0)
    }

    private var lastRunText: String {
        guard let epochMs = zone.lastWateredDate else { return "—" }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000)
        return formatDateOrTime(date)
    }

    private var nextRunText: String {
        guard let device else { return "—" }
        let schedules = device.schedules(forZoneId: zone.id)
        guard !schedules.isEmpty else { return "—" }

        let now = Date()
        let calendar = Calendar.current
        var candidates: [(date: Date, isFlex: Bool)] = []

        for entry in schedules {
            let rule = entry.rule
            guard rule.enabled else { continue }

            // FLEX schedules (no startHour) — Rachio computes the time internally,
            // not exposed via public API. Estimate from lastWateredDate if available.
            let isFlex = rule.startHour == nil
            var hour = rule.startHour ?? 12  // default to noon if no data
            var minute = rule.startMinute ?? 0
            
            if isFlex, let lastMs = zone.lastWateredDate {
                // Use last run time as estimate for FLEX schedule
                let lastRun = Date(timeIntervalSince1970: Double(lastMs) / 1000)
                hour = calendar.component(.hour, from: lastRun)
                minute = calendar.component(.minute, from: lastRun)
            }
            let types = rule.scheduleJobTypes ?? []

            // DAY_OF_WEEK_N → fixed weekday schedule
            // Rachio: 0=Sun…6=Sat, Swift weekday: 1=Sun…7=Sat
            let fixedWeekdays = types.compactMap { t -> Int? in
                guard t.hasPrefix("DAY_OF_WEEK_"), let n = Int(t.dropFirst("DAY_OF_WEEK_".count)) else { return nil }
                return n + 1
            }

            if !fixedWeekdays.isEmpty {
                for offset in 0..<8 {
                    guard let candidate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                    let weekday = calendar.component(.weekday, from: candidate)
                    guard fixedWeekdays.contains(weekday) else { continue }
                    var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
                    comps.hour = hour; comps.minute = minute; comps.second = 0
                    if let runDate = calendar.date(from: comps), runDate > now {
                        candidates.append((runDate, isFlex))
                        break
                    }
                }
            } else {
                var intervalDays = 1
                for t in types {
                    if t.hasPrefix("INTERVAL_"), let n = Int(t.dropFirst("INTERVAL_".count)), n > 0 {
                        intervalDays = n; break
                    }
                }
                for offset in 0...intervalDays {
                    guard let candidate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                    var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
                    comps.hour = hour; comps.minute = minute; comps.second = 0
                    if let runDate = calendar.date(from: comps), runDate > now {
                        candidates.append((runDate, isFlex))
                        break
                    }
                }
            }
        }

        guard let next = candidates.min(by: { $0.date < $1.date }) else { return "—" }
        // Show time if today, otherwise show date — same for fixed and FLEX
        return formatDateOrTime(next.date)
    }

    /// If date is today, show time only; otherwise show day/date without time
    private func formatDateOrTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "EEE, MMM d"
        }
        return formatter.string(from: date)
    }

    private var zoneGradient: LinearGradient {
        let colors = zoneColors(for: zone.name)
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var zoneIcon: String {
        let name = zone.name.lowercased()
        if name.contains("citrus") || name.contains("orange") { return "leaf.circle.fill" }
        if name.contains("drip") || name.contains("whole") { return "drop.fill" }
        if name.contains("ficus") || name.contains("tree") { return "tree.fill" }
        if name.contains("lawn") || name.contains("grass") { return "leaf.fill" }
        if name.contains("rose") || name.contains("flower") { return "camera.macro" }
        return "leaf.fill"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image + weekly ring
            ZStack(alignment: .topTrailing) {
                // Zone image from Rachio — disk-cached with ETag change detection
                if let imageUrl = zone.imageUrl, !imageUrl.isEmpty {
                    CachedZoneImage(
                        urlString: imageUrl,
                        fallback: AnyView(fallbackZoneImage)
                    )
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
                } else {
                    fallbackZoneImage
                }

                // Weekly runtime ring
                WeeklyRing(fraction: weeklyFraction, text: weeklyRuntimeText)
                    .frame(width: 52, height: 52)
                    .offset(x: -6, y: 6)
            }

            // Zone name
            Text(zone.name)
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .padding(.top, DS.Spacing.md)
                .padding(.horizontal, DS.Spacing.md)

            // Info rows — always fixed height so all tiles align regardless of sensor presence
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                // Soil Moisture — always reserves space, hidden if no sensors
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundStyle(moistureColor)
                    Text("Soil Moisture")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    if let m = moisture {
                        Text("\(Int(m))%")
                            .font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(moistureColor)
                    } else {
                        Text("—")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .opacity(moisture != nil ? 1 : 0) // invisible but still takes space

                // Last Run
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("Last Run")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(lastRunText)
                        .font(DS.Font.caption.weight(.medium))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Next Run
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("Next Run")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(nextRunText)
                        .font(DS.Font.caption.weight(.medium))
                        .foregroundStyle(DS.Color.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.sm)
            .padding(.bottom, DS.Spacing.md)
        }
        .background(DS.Color.card)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
        .shadow(color: DS.Color.cardShadow, radius: 4, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .stroke(isActive ? DS.Color.online : Color.clear, lineWidth: 2)
                .opacity(isActive ? (pulse ? 1.0 : 0.4) : 0)
        )
        .onTapGesture {
            if isActive {
                onStop()
            } else {
                showDurationSheet = true
            }
        }
        .sheet(isPresented: $showDurationSheet) {
            DurationPickerSheet(
                zoneName: zone.name,
                durations: durations,
                selectedDuration: $selectedDuration
            ) { duration in
                onStart(duration * 60)
                showDurationSheet = false
            }
            .presentationDetents([.height(340)])
        }
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
        .onAppear { if isActive { pulse = true } }
        .onChange(of: isActive) { _, running in pulse = running }
    }

    // MARK: - Subviews

    private var fallbackZoneImage: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card)
            .fill(zoneGradient)
            .frame(height: 100)
            .overlay(
                Image(systemName: zoneIcon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            )
    }

    // MARK: - Helpers

    private func zoneColors(for name: String) -> [Color] {
        let n = name.lowercased()
        if n.contains("rose") || n.contains("flower") {
            return [Color(hex: "e91e63"), Color(hex: "f06292")]
        }
        if n.contains("citrus") || n.contains("orange") {
            return [Color(hex: "ff9800"), Color(hex: "ffb74d")]
        }
        if n.contains("tomato") {
            return [Color(hex: "d32f2f"), Color(hex: "4caf50")]
        }
        if n.contains("lettuce") || n.contains("herb") || n.contains("garden") {
            return [Color(hex: "66bb6a"), Color(hex: "aed581")]
        }
        if n.contains("ficus") || n.contains("tree") {
            return [Color(hex: "2e7d32"), Color(hex: "4caf50")]
        }
        if n.contains("drip") || n.contains("whole") {
            return [Color(hex: "1976d2"), Color(hex: "64b5f6")]
        }
        if n.contains("backyard") || n.contains("gndcover") || n.contains("groundcover") {
            return [Color(hex: "43a047"), Color(hex: "81c784")]
        }
        if n.contains("lawn") || n.contains("front") {
            return [Color(hex: "4caf50"), Color(hex: "8bc34a")]
        }
        // Default green
        return [Color(hex: "388e3c"), Color(hex: "66bb6a")]
    }
}

// MARK: - Weekly Runtime Ring

private struct WeeklyRing: View {
    let fraction: Double
    let text: String

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(DS.Color.card)
                .shadow(color: DS.Color.cardShadow, radius: 4, x: 0, y: 2)

            // Track
            Circle()
                .stroke(DS.Color.separator, lineWidth: 4)
                .padding(4)

            // Progress arc
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    LinearGradient(
                        colors: [DS.Color.accent, DS.Color.accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)

            // Text
            VStack(spacing: 0) {
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Color.textPrimary)
                Text("/week")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.md) {
        ZoneCardView(
            zone: RachioZone(id: "1", name: "Front Lawn", enabled: true, zoneNumber: 1,
                             lastWateredDate: Int(Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000),
                             lastWateredDuration: 600, imageUrl: nil),
            device: nil, moisture: 34.5, isActive: false, onStart: { _ in }, onStop: {}
        )
        ZoneCardView(
            zone: RachioZone(id: "2", name: "Tomato Garden", enabled: true, zoneNumber: 4,
                             lastWateredDate: nil, lastWateredDuration: nil, imageUrl: nil),
            device: nil, moisture: nil, isActive: true, onStart: { _ in }, onStop: {}
        )
    }
    .padding()
    .dsBackground()
}
