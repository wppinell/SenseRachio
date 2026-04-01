import SwiftUI

struct SensorRowView: View {
    let sensor: SensorConfig
    let reading: SensorReading?
    var predictedDryDate: Date? = nil
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

    private var moistureSecondaryRow: some View {
        coloredMoistureLabel(suffix: suffix(for: secondaryLabel),
                             color: hasAlias ? DS.Color.textTertiary : DS.Color.textSecondary)
    }

    private func moistureTertiaryRow(_ text: String) -> some View {
        coloredMoistureLabel(suffix: tempDisplay.map { " · \($0)" } ?? "",
                             color: DS.Color.textSecondary)
    }

    private func coloredMoistureLabel(suffix: String, color: Color) -> some View {
        (Text("\(Int(moisture))%").foregroundStyle(moistureColor) +
         Text(suffix).foregroundStyle(color))
            .font(DS.Font.caption)
    }

    private func suffix(for label: String) -> String {
        switch label {
        case "moisture":    return " moisture"
        case "lastUpdated": return reading.map { " · Updated \($0.recordedAt.relativeFormatted)" } ?? ""
        case "group":       return sensor.groupId.map { " · \($0)" } ?? ""
        default:            return tempDisplay.map { " · \($0)" } ?? " moisture"
        }
    }

    private func relativeDryDate(_ date: Date) -> String {
        let hours = date.timeIntervalSinceNow / 3600
        if hours < 24 {
            return "in \(Int(hours))h"
        } else {
            let days = hours / 24
            if days < 2 { return "tomorrow" }
            return "in \(Int(days)) days"
        }
    }
    
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
                    if !isDisabled, hasReading {
                        moistureSecondaryRow
                    }
                    if tertiaryText != nil, !isDisabled {
                        moistureTertiaryRow("")
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
            }

            // Moisture bar
            if hasReading {
                DSMoistureBar(value: moisture)
            }

            // Status indicator — show for critical, dry, or high (not for disabled sensors)
            if hasReading && !isDisabled {
                let isCritical = moisture < autoWaterThreshold
                let isDry = moisture < dryThreshold
                let isHigh = moisture >= highThreshold
                
                if isCritical {
                    // Critical — needs water now
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.error)
                        Text("Critical")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.Color.error)
                        if sensor.autoWaterEnabled, sensor.linkedZoneId != nil {
                            Spacer()
                            Label("Auto", systemImage: "drop.fill")
                                .font(DS.Font.footnote)
                                .foregroundStyle(DS.Color.accent)
                        }
                    }
                } else if isDry {
                    // Dry — getting low
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.warning)
                        Text("Dry")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.Color.warning)
                    }
                } else if let dryDate = predictedDryDate, !isCritical, !isDry {
                    // Trending dry — show prediction
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.warning.opacity(0.8))
                        Text("Dries \(relativeDryDate(dryDate))")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.Color.warning.opacity(0.8))
                    }
                } else if isHigh {
                    // High — well watered
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "0EA5E9"))
                        Text("High")
                            .font(DS.Font.footnote)
                            .foregroundStyle(Color(hex: "0EA5E9"))
                    }
                }
                // If OK (between dry and high), show nothing — clean row
            }
        }
        .padding(DS.Spacing.lg)
        .background(indicatorStyle == "coloredBackground" && hasReading ? moistureColor.opacity(0.06) : DS.Color.card)
        .dsCard()
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
