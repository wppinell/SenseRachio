import SwiftUI

struct SensorLabelsView: View {
    @AppStorage(AppStorageKey.sensorPrimaryLabel) private var primaryLabel = "name"
    @AppStorage(AppStorageKey.sensorSecondaryLabel) private var secondaryLabel = "moistureTemp"
    @AppStorage(AppStorageKey.statusIndicatorStyle) private var indicatorStyle = "coloredDot"

    // Preview data
    private let previewSensor = SensorConfig(
        id: "preview", name: "Garden Bed A", eui: "2CF7F1C044200006",
        moistureThreshold: 30
    )
    private let previewReading = SensorReading(
        eui: "2CF7F1C044200006", moisture: 35.5, tempC: 21.3
    )

    var body: some View {
        List {
            Section {
                Picker("Primary Line", selection: $primaryLabel) {
                    Text("Name").tag("name")
                    Text("EUI").tag("eui")
                    Text("Group").tag("group")
                }
            } header: { Text("Primary Line") }
             footer: { Text("The main bold label shown for each sensor.") }

            Section {
                Picker("Secondary Line", selection: $secondaryLabel) {
                    Text("Moisture + Temperature").tag("moistureTemp")
                    Text("Moisture Only").tag("moisture")
                    Text("Last Updated").tag("lastUpdated")
                    Text("Group").tag("group")
                }
            } header: { Text("Secondary Line") }
             footer: { Text("Supplemental information shown below the primary label.") }

            Section {
                Picker("Status Indicator", selection: $indicatorStyle) {
                    HStack {
                        DSStatusDot(status: .online)
                        Text("Colored Dot")
                    }.tag("coloredDot")
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Color.online.opacity(0.15))
                            .frame(width: 16, height: 12)
                        Text("Colored Background")
                    }.tag("coloredBackground")
                    HStack {
                        Image(systemName: "minus")
                            .foregroundStyle(DS.Color.textTertiary)
                        Text("None")
                    }.tag("none")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("Status Indicator") }

            // Live Preview
            Section {
                SensorRowView(sensor: previewSensor, reading: previewReading)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
            } header: { Text("Preview") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sensor Labels")
        .navigationBarTitleDisplayMode(.inline)
    }
}
