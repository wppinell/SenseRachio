import SwiftUI
import SwiftData

struct SensorZoneLinkView: View {
    @Query private var sensors: [SensorConfig]
    @Query private var zones: [ZoneConfig]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if sensors.isEmpty {
            Text("No sensors found. Load sensors in the Sensors tab first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ForEach(sensors) { sensor in
                SensorLinkRow(sensor: sensor, zones: zones)
            }
        }
    }
}

// MARK: - Sensor Link Row

struct SensorLinkRow: View {
    let sensor: SensorConfig
    let zones: [ZoneConfig]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedZoneId: String = ""
    @State private var threshold: Double = 30.0

    private var zoneOptions: [(id: String, name: String)] {
        var options: [(String, String)] = [("", "None")]
        options += zones.map { ($0.id, $0.name) }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sensor.name)
                .font(.subheadline.bold())

            // Zone Picker
            HStack {
                Text("Linked Zone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Zone", selection: $selectedZoneId) {
                    ForEach(zoneOptions, id: \.id) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
            }

            // Threshold Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Moisture Threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(threshold))%")
                        .font(.caption.bold())
                        .foregroundStyle(thresholdColor)
                }
                Slider(value: $threshold, in: 0...100, step: 1)
                    .tint(thresholdColor)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            selectedZoneId = sensor.linkedZoneId ?? ""
            threshold = sensor.moistureThreshold ?? 30.0
        }
        .onChange(of: selectedZoneId) { _, newValue in
            sensor.linkedZoneId = newValue.isEmpty ? nil : newValue
            try? modelContext.save()
        }
        .onChange(of: threshold) { _, newValue in
            sensor.moistureThreshold = newValue
            try? modelContext.save()
        }
    }

    private var thresholdColor: Color {
        if threshold >= 40 { return .green }
        if threshold >= 25 { return .yellow }
        return .red
    }
}

#Preview {
    Form {
        Section("Sensor-Zone Links") {
            SensorZoneLinkView()
        }
    }
}
