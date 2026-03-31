import SwiftUI

struct ZoneRowView: View {
    let zone: RachioZone
    let device: RachioDevice?
    let isActive: Bool
    let onStart: (Int) -> Void
    let onStop: () -> Void

    @State private var showDurationSheet = false
    @State private var selectedDuration = 10
    @AppStorage(AppStorageKey.durationUnit) private var durationUnit = "minutes"

    private let durations = [5, 10, 15, 20, 30]

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // Zone number badge
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.badge)
                    .fill(isActive ? DS.Color.online : DS.Color.accent.opacity(0.12))
                Text("\(zone.zoneNumber ?? 0)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .white : DS.Color.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(zone.name)
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    if isActive {
                        DSBadge(text: "Running", color: DS.Color.online, small: true)
                    }
                }
                if let subtitle = lastWateredSubtitle {
                    Text(subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                if let schedule = weeklyScheduleSummary {
                    Text(schedule)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }

            Spacer()

            if isActive {
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(DS.Font.label)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .tint(DS.Color.error)
                .controlSize(.small)
            } else {
                Button {
                    showDurationSheet = true
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(DS.Font.label)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .tint(DS.Color.accent)
                .controlSize(.small)
            }
        }
        .padding(DS.Spacing.lg)
        .background(isActive ? DS.Color.online.opacity(0.06) : DS.Color.card)
        .dsCard()
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
    }

    private var weeklyScheduleSummary: String? {
        guard let device else { return nil }
        let schedules = device.schedules(forZoneId: zone.id)
        guard !schedules.isEmpty else { return nil }
        // Each schedule runs duration × runsPerWeek seconds per week
        let totalMinutes = Int(schedules.reduce(0.0) { $0 + (Double($1.duration) / 60.0 * $1.rule.runsPerWeekDouble) }.rounded())
        let scheduleNames = schedules.map { $0.rule.name }.joined(separator: ", ")
        let durationStr: String
        if totalMinutes >= 90 {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            durationStr = m > 0 ? "\(h)h \(m)m/week" : "\(h)h/week"
        } else {
            durationStr = "\(totalMinutes) min/week"
        }
        return "📅 \(durationStr) · \(scheduleNames)"
    }

    private var lastWateredSubtitle: String? {
        guard let epochMs = zone.lastWateredDate else { return nil }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        if let dur = zone.lastWateredDuration {
            return "Watered \(relative) · \(formatDuration(dur))"
        }
        return "Watered \(relative)"
    }

    private func formatDuration(_ seconds: Int) -> String {
        switch durationUnit {
        case "seconds": return "\(seconds)s"
        case "hoursMinutes":
            if seconds >= 3600 {
                let hours = Double(seconds) / 3600.0
                return String(format: hours.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fh" : "%.1fh", hours)
            }
            return "\(seconds / 60)m"
        default:
            let m = seconds / 60
            if m >= 60 {
                let hours = Double(m) / 60.0
                return String(format: hours.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fh" : "%.1fh", hours)
            }
            let s = seconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        }
    }
}

// MARK: - Duration Picker Sheet

struct DurationPickerSheet: View {
    let zoneName: String
    let durations: [Int]
    @Binding var selectedDuration: Int
    let onConfirm: (Int) -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Handle
            Capsule()
                .fill(DS.Color.separator)
                .frame(width: 36, height: 4)
                .padding(.top, DS.Spacing.md)

            VStack(spacing: DS.Spacing.xs) {
                Text("Run \(zoneName)")
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Select duration")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            HStack(spacing: DS.Spacing.sm) {
                ForEach(durations, id: \.self) { minutes in
                    Button {
                        selectedDuration = minutes
                        HapticFeedback.impact(.light)
                    } label: {
                        VStack(spacing: DS.Spacing.xs) {
                            Text("\(minutes)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("min")
                                .font(DS.Font.footnote)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(selectedDuration == minutes ? DS.Color.accent : DS.Color.background)
                        .foregroundStyle(selectedDuration == minutes ? .white : DS.Color.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)

            DSPrimaryButton(label: "Start Zone", icon: "play.fill") {
                onConfirm(selectedDuration)
            }
            .padding(.horizontal, DS.Spacing.lg)

            Spacer()
        }
        .background(DS.Color.background.ignoresSafeArea())
    }
}

#Preview {
    VStack(spacing: DS.Spacing.sm) {
        ZoneRowView(
            zone: RachioZone(id: "1", name: "Front Lawn", enabled: true, zoneNumber: 1,
                             lastWateredDate: Int(Date().addingTimeInterval(-172800).timeIntervalSince1970 * 1000),
                             lastWateredDuration: 600, imageUrl: nil),
            device: nil, isActive: false, onStart: { _ in }, onStop: {}
        )
        ZoneRowView(
            zone: RachioZone(id: "2", name: "Tomato Garden", enabled: true, zoneNumber: 4,
                             lastWateredDate: nil, lastWateredDuration: nil, imageUrl: nil),
            device: nil, isActive: true, onStart: { _ in }, onStop: {}
        )
    }
    .padding()
    .dsBackground()
}
