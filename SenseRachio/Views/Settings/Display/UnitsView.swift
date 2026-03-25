import SwiftUI

struct UnitsView: View {
    @AppStorage(AppStorageKey.temperatureUnit) private var tempUnit = "celsius"
    @AppStorage(AppStorageKey.moistureUnit) private var moistureUnit = "percent"
    @AppStorage(AppStorageKey.durationUnit) private var durationUnit = "minutes"
    @AppStorage(AppStorageKey.volumeUnit) private var volumeUnit = "gallons"

    var body: some View {
        List {
            Section {
                Picker("Temperature", selection: $tempUnit) {
                    Text("°C (Celsius)").tag("celsius")
                    Text("°F (Fahrenheit)").tag("fahrenheit")
                }

                HStack {
                    Text("Preview")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(tempUnit == "fahrenheit" ? "77.0°F" : "25.0°C")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                .font(DS.Font.caption)
            } header: { Text("Temperature") }

            Section {
                Picker("Moisture", selection: $moistureUnit) {
                    Text("Percent (%)").tag("percent")
                    Text("Raw Value").tag("raw")
                }

                HStack {
                    Text("Preview")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(moistureUnit == "raw" ? "2048" : "42%")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                .font(DS.Font.caption)
            } header: { Text("Moisture") }

            Section {
                Picker("Duration", selection: $durationUnit) {
                    Text("Minutes (10m)").tag("minutes")
                    Text("Hours:Minutes (0:10)").tag("hoursMinutes")
                    Text("Seconds (600s)").tag("seconds")
                }

                HStack {
                    Text("Preview")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(durationPreview)
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                .font(DS.Font.caption)
            } header: { Text("Duration") }

            Section {
                Picker("Volume", selection: $volumeUnit) {
                    Text("Gallons").tag("gallons")
                    Text("Liters").tag("liters")
                }
            } header: { Text("Volume") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var durationPreview: String {
        switch durationUnit {
        case "hoursMinutes": return "0:10"
        case "seconds":      return "600s"
        default:             return "10m"
        }
    }
}
