import SwiftUI

struct SensorRowView: View {
    let sensor: SensorConfig
    let reading: SensorReading?
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"
    @AppStorage(AppStorageKey.sensorPrimaryLabel) private var primaryLabel = "name"
    @AppStorage(AppStorageKey.sensorSecondaryLabel) private var secondaryLabel = "moistureTemp"
    @AppStorage(AppStorageKey.statusIndicatorStyle) private var indicatorStyle = "coloredDot"

    private var moisture: Double { reading?.moisture ?? 0 }
    private var hasReading: Bool { reading != nil }
    private var moistureColor: Color { DS.Color.moisture(moisture) }

    private var primaryText: String {
        switch primaryLabel {
        case "eui":   return sensor.eui
        case "group": return sensor.groupId ?? sensor.name
        default:      return sensor.name
        }
    }

    private var secondaryText: String? {
        guard hasReading else { return nil }
        switch secondaryLabel {
        case "moisture":     return "\(Int(moisture))% moisture"
        case "lastUpdated":  return reading.map { "Updated \($0.recordedAt.relativeFormatted)" }
        case "group":        return sensor.groupId
        default:             return tempDisplay.map { "\(Int(moisture))% · \($0)" }
        }
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
                        status: isDisabled ? .unknown : (!hasReading ? .unknown : moisture < 25 ? .offline : moisture < 40 ? .warning : .online),
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
                            .foregroundStyle(DS.Color.textSecondary)
                    } else if isDisabled {
                        Text("Not collecting data")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    } else if !hasReading {
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

            // Threshold indicator
            if let threshold = sensor.moistureThreshold, hasReading {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: moisture < threshold ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(moisture < threshold ? DS.Color.error : DS.Color.online)
                    Text("Threshold: \(Int(threshold))%")
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
                sensor: SensorConfig(id: "1", name: "Garden Bed A", eui: "2CF7F1C044200006", moistureThreshold: 30, autoWaterEnabled: true),
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
