import SwiftUI
import SwiftData
import Charts

struct SensorDetailView: View {
    let sensor: SensorConfig
    let reading: SensorReading?

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"
    @AppStorage(AppStorageKey.trendChartPeriod) private var chartPeriod = "24h"

    @Query private var allReadings: [SensorReading]
    @Query private var zones: [ZoneConfig]
    @Query(sort: \ZoneGroup.sortOrder) private var groups: [ZoneGroup]

    @State private var isRunningZone = false
    @State private var runError: String? = nil
    @State private var showRunSuccess = false

    private var moisture: Double { reading?.moisture ?? 0 }
    private var hasReading: Bool { reading != nil }
    private var moistureColor: Color { DS.Color.moisture(moisture) }

    private var linkedZone: ZoneConfig? {
        guard let id = sensor.linkedZoneId else { return nil }
        return zones.first(where: { $0.id == id })
    }

    private var sensorGroup: ZoneGroup? {
        guard let gid = sensor.groupId else { return nil }
        return groups.first(where: { $0.id == gid })
    }

    private var tempDisplay: String? {
        guard let t = reading?.tempC else { return nil }
        if tempUnit == "fahrenheit" {
            return String(format: "%.1f°F", t * 9/5 + 32)
        }
        return String(format: "%.1f°C", t)
    }

    private var statusLabel: String {
        guard hasReading else { return "Unknown" }
        if moisture < 25 { return "DRY" }
        if moisture < 40 { return "LOW" }
        return "OK"
    }

    private var historyReadings: [(Date, Double)] {
        let cutoff: Date
        switch chartPeriod {
        case "6h":  cutoff = Date().addingTimeInterval(-6 * 3600)
        case "12h": cutoff = Date().addingTimeInterval(-12 * 3600)
        case "7d":  cutoff = Date().addingTimeInterval(-7 * 86400)
        default:    cutoff = Date().addingTimeInterval(-86400)
        }
        return allReadings
            .filter { $0.eui == sensor.eui && $0.recordedAt >= cutoff }
            .map { ($0.recordedAt, $0.moisture) }
            .sorted(by: { $0.0 < $1.0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header Card
                headerCard
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)

                // Current Readings
                DSSectionHeader(title: "Current Readings")
                readingsCard
                    .padding(.horizontal, DS.Spacing.lg)

                // History Chart
                DSSectionHeader(title: "History")
                historyCard
                    .padding(.horizontal, DS.Spacing.lg)

                // Linked Zone
                if let zone = linkedZone {
                    DSSectionHeader(title: "Linked Zone")
                    linkedZoneCard(zone: zone)
                        .padding(.horizontal, DS.Spacing.lg)
                }

                // Group
                if let group = sensorGroup {
                    DSSectionHeader(title: "Group")
                    groupCard(group: group)
                        .padding(.horizontal, DS.Spacing.lg)
                }

                // Settings
                DSSectionHeader(title: "Settings")
                settingsCard
                    .padding(.horizontal, DS.Spacing.lg)

                // Run Linked Zone button
                if linkedZone != nil {
                    VStack(spacing: DS.Spacing.sm) {
                        if let err = runError {
                            DSInlineBanner(message: err, style: .error)
                        }
                        if showRunSuccess {
                            DSInlineBanner(message: "Zone started successfully.", style: .success)
                        }
                        DSPrimaryButton(
                            label: "Run Linked Zone",
                            icon: "play.fill",
                            isLoading: isRunningZone
                        ) {
                            Task { await runLinkedZone() }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.lg)
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .navigationTitle(sensor.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: DS.Spacing.lg) {
            DSCircleGauge(value: hasReading ? moisture : 0, size: 80)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSBadge(text: statusLabel, color: moistureColor)
                Text(sensor.eui)
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
                if let updated = reading?.recordedAt {
                    Label(updated.relativeFormatted, systemImage: "clock")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer()
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Readings Card

    private var readingsCard: some View {
        HStack(spacing: 0) {
            ReadingCell(
                icon: "humidity.fill",
                iconColor: DS.Color.accent,
                value: hasReading ? "\(Int(moisture))%" : "—",
                label: "Moisture",
                valueColor: hasReading ? moistureColor : DS.Color.textTertiary
            )
            Divider().frame(height: 50)
            ReadingCell(
                icon: "thermometer.medium",
                iconColor: DS.Color.warning,
                value: tempDisplay ?? "—",
                label: "Temperature",
                valueColor: DS.Color.textPrimary
            )
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - History Card

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Moisture history")
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Picker("Period", selection: $chartPeriod) {
                    Text("6h").tag("6h")
                    Text("12h").tag("12h")
                    Text("24h").tag("24h")
                    Text("7d").tag("7d")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if historyReadings.count >= 2 {
                Chart {
                    ForEach(historyReadings, id: \.0) { point in
                        AreaMark(
                            x: .value("Time", point.0),
                            y: .value("Moisture", point.1)
                        )
                        .foregroundStyle(moistureColor.opacity(0.15))
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value("Moisture", point.1)
                        )
                        .foregroundStyle(moistureColor)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Time", point.0),
                            y: .value("Moisture", point.1)
                        )
                        .foregroundStyle(moistureColor)
                        .symbolSize(20)
                    }
                    // Threshold reference lines
                    RuleMark(y: .value("Dry", 25))
                        .foregroundStyle(DS.Color.error.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .trailing) {
                            Text("Dry").font(DS.Font.footnote).foregroundStyle(DS.Color.error)
                        }
                    RuleMark(y: .value("Low", 40))
                        .foregroundStyle(DS.Color.warning.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .trailing) {
                            Text("Low").font(DS.Font.footnote).foregroundStyle(DS.Color.warning)
                        }
                }
                .frame(height: 160)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 40, 75, 100]) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%").font(DS.Font.footnote)
                            }
                        }
                        AxisGridLine()
                    }
                }
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("Not enough data for the selected period")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Linked Zone Card

    private func linkedZoneCard(zone: ZoneConfig) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "drop.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 28, height: 28)
                .background(DS.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                if sensor.autoWaterEnabled {
                    Label("Auto-water enabled", systemImage: "drop.fill")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.online)
                } else {
                    Text("Auto-water off")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer()
            if let threshold = sensor.moistureThreshold {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(threshold))%")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.moisture(threshold))
                    Text("threshold")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Group Card

    private func groupCard(group: ZoneGroup) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: group.iconName)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 28, height: 28)
                .background(DS.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(group.name)
                .font(DS.Font.cardTitle)
                .foregroundStyle(DS.Color.textPrimary)

            Spacer()

            Text("\(group.assignedZoneIds.count) zones")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Alias
            HStack {
                Text("Alias")
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                TextField("Sensor alias", text: Binding(
                    get: { sensor.name },
                    set: { newValue in
                        sensor.name = newValue
                        try? modelContext.save()
                    }
                ))
                .font(DS.Font.cardBody)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
            }
            .padding(DS.Spacing.lg)
            
            Divider().padding(.leading, DS.Spacing.lg)
            
            // Enable/Disable Sensor
            HStack {
                Label("Enabled", systemImage: "power")
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !sensor.isHiddenFromGraphs },
                    set: { newValue in
                        sensor.isHiddenFromGraphs = !newValue
                        _ = try? modelContext.save()
                    }
                ))
                .labelsHidden()
                .tint(DS.Color.accent)
            }
            .padding(DS.Spacing.lg)
            
            if sensor.isHiddenFromGraphs {
                Text("Disabled sensors are grayed out and won't receive new readings.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)
            }
        }
        .dsCard()
    }

    // MARK: - Actions

    private func runLinkedZone() async {
        guard let zoneId = sensor.linkedZoneId else { return }
        isRunningZone = true
        runError = nil
        showRunSuccess = false

        do {
            try await RachioAPI.shared.startZone(id: zoneId, duration: 600) // 10 min default
            showRunSuccess = true
        } catch {
            runError = error.localizedDescription
        }
        isRunningZone = false
    }
}

// MARK: - Reading Cell

private struct ReadingCell: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    var valueColor: Color = DS.Color.textPrimary

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
            Text(value)
                .font(DS.Font.statSmall)
                .foregroundStyle(valueColor)
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
