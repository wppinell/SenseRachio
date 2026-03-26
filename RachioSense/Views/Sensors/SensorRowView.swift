import SwiftUI

struct SensorRowView: View {
    let sensor: SensorConfig
    let reading: SensorReading?
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"
    @AppStorage(AppStorageKey.sensorPrimaryLabel) private var primaryLabel = "name"
    @AppStorage(AppStorageKey.sensorSecondaryLabel) private var secondaryLabel = "moistureTemp"
    @AppStorage(AppStorageKey.statusIndicatorStyle) private var indicatorStyle = "coloredDot"
    @AppStorage(AppStorageKey.autoWaterThreshold) private var autoWaterThreshold: Double = 20
    @AppStorage(AppStorageKey.dryThreshold) private var dryThreshold: Double = 25
    @AppStorage(AppStorageKey.lowThreshold) private var highThreshold: Double = 40  // "High Level"

    private var moisture: Double { reading?.moisture ?? 0 }
    private var hasReading: Bool { reading != nil }

    private var moistureColor: Color {
        guard hasReading else { return DS.Color.textTertiary }
        if moisture < autoWaterThreshold { return DS.Color.error }         // red — needs water now
        if moisture < dryThreshold       { return DS.Color.warning }       // yellow — getting dry
        if moisture < highThreshold      { return DS.Color.online }        // green — good
        return Color(hex: "0EA5E9")                                        // blue — above high
    }

    private var primaryText: String {
        sensor.displayName
    }
    
    private var hasAlias: Bool {
        sensor.alias != nil && !sensor.alias!.isEmpty
    }

    private var secondaryText: String? {
        // If alias is set, show original name first
        if hasAlias {
            return sensor.name
        }
        guard hasReading else { return nil }
        switch secondaryLabel {
        case "moisture":     return "\(Int(moisture))% moisture"
        case "lastUpdated":  return reading.map { "Updated \($0.recordedAt.relativeFormatted)" }
        case "group":        return sensor.groupId
        default:             return tempDisplay.map { "\(Int(moisture))% · \($0)" }
        }
    }
    
    private var tertiaryText: String? {
        // If alias is set, show reading info as tertiary
        guard hasAlias, hasReading else { return nil }
        return tempDisplay.map { "\(Int(moisture))% · \($0)" }
    }

    private var tempDisplay: String? {
        guard let tempC = reading?.tempC else { return nil }
        if tempUnit == "fahrenheit" {
            return String(format: "%.1f°F", tempC * 9/5 + 32)
        }
        return String(format: "%.1f°C", tempC)
    }

    private var isDisabled: Bool { sensor.isHiddenFromGraphs }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                // Status indicator
                if indicatorStyle == "coloredDot" {
                    DSStatusDot(
                        status: isDisabled ? .unknown : (!hasReading ? .unknown : moisture < autoWaterThreshold ? .offline : moisture < dryThreshold ? .warning : .online),
                        size: 10
                    )
                    .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(primaryText)
                            .font(DS.Font.cardTitle)
                            .foregroundStyle(isDisabled ? DS.Color.textTertiary : (indicatorStyle == "coloredBackground" ? moistureColor : DS.Color.textPrimary))
                        if isDisabled {
                            Text("DISABLED")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DS.Color.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DS.Color.textTertiary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    if let secondary = secondaryText, !isDisabled {
                        Text(secondary)
                            .font(DS.Font.caption)
                            .foregroundStyle(hasAlias ? DS.Color.textTertiary : DS.Color.textSecondary)
                    }
                    if let tertiary = tertiaryText, !isDisabled {
                        Text(tertiary)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    } else if isDisabled {
                        Text("Not collecting data")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    } else if !hasReading && !hasAlias {
                        Text("No data yet")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }

                Spacer()

                // Moisture value
                VStack(alignment: .trailing, spacing: 2) {
                    if hasReading {
                        Text("\(Int(moisture))%")
                            .font(DS.Font.statSmall)
                            .foregroundStyle(moistureColor)
                    } else {
                        Text("—")
                            .font(DS.Font.statSmall)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    if let temp = tempDisplay, secondaryLabel == "moistureTemp" {
                        Text(temp)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }

            // Moisture bar
            if hasReading {
                DSMoistureBar(value: moisture)
            }

            // Threshold indicator using global thresholds
            if hasReading {
                let threshold = sensor.autoWaterEnabled ? autoWaterThreshold : dryThreshold
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: moisture < threshold ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(moisture < threshold ? DS.Color.error : DS.Color.online)
                    Text("\(sensor.autoWaterEnabled ? "Auto-water" : "Dry alert"): \(Int(threshold))%")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.Color.textSecondary)

                    if sensor.autoWaterEnabled, sensor.linkedZoneId != nil {
                        Spacer()
                        Label("Auto", systemImage: "drop.fill")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.Color.accent)
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(indicatorStyle == "coloredBackground" && hasReading ? moistureColor.opacity(0.06) : DS.Color.card)
        .dsCard()
    }
}

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

#Preview {
    ScrollView {
        VStack(spacing: DS.Spacing.sm) {
            SensorRowView(
                sensor: SensorConfig(id: "1", name: "Garden Bed A", eui: "2CF7F1C044200006", autoWaterEnabled: true),
                reading: SensorReading(eui: "2CF7F1C044200006", moisture: 22.5, tempC: 21.3)
            )
            SensorRowView(
                sensor: SensorConfig(id: "2", name: "Front Lawn", eui: "2CF7F1C044200007"),
                reading: SensorReading(eui: "2CF7F1C044200007", moisture: 35.2, tempC: 23.1)
            )
            SensorRowView(
                sensor: SensorConfig(id: "3", name: "Backyard", eui: "2CF7F1C044200008"),
                reading: SensorReading(eui: "2CF7F1C044200008", moisture: 62.0, tempC: 19.8)
            )
            SensorRowView(
                sensor: SensorConfig(id: "4", name: "Herb Garden", eui: "2CF7F1C044200009"),
                reading: nil
            )
        }
        .padding()
    }
    .dsBackground()
}
