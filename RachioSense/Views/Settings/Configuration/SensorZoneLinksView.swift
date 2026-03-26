import SwiftUI
import SwiftData

struct SensorZoneLinksView: View {
    @Query private var sensors: [SensorConfig]
    @Query private var zones: [ZoneConfig]
    @Environment(\.modelContext) private var modelContext

    private var visibleSensors: [SensorConfig] { sensors.filter { !$0.isHiddenFromGraphs } }
    private var linkedSensors: [SensorConfig] { visibleSensors.filter { $0.linkedZoneId != nil } }
    private var unlinkedSensors: [SensorConfig] { visibleSensors.filter { $0.linkedZoneId == nil } }

    var body: some View {
        List {
            if sensors.isEmpty {
                Section {
                    DSEmptyState(
                        icon: "link",
                        title: "No Sensors Found",
                        message: "Open the Sensors tab to load your SenseCraft devices first."
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                }
            }

            if !linkedSensors.isEmpty {
                Section {
                    ForEach(linkedSensors) { sensor in
                        NavigationLink {
                            SensorLinkDetailView(sensor: sensor, zones: zones)
                        } label: {
                            SensorLinkRowLabel(sensor: sensor, zones: zones)
                        }
                    }
                } header: {
                    Text("Linked Sensors (\(linkedSensors.count))")
                }
            }

            if !unlinkedSensors.isEmpty {
                Section {
                    ForEach(unlinkedSensors) { sensor in
                        NavigationLink {
                            SensorLinkDetailView(sensor: sensor, zones: zones)
                        } label: {
                            SensorLinkRowLabel(sensor: sensor, zones: zones)
                        }
                    }
                } header: {
                    Text("Unlinked Sensors (\(unlinkedSensors.count))")
                }
            }


        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sensor-Zone Links")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Row Label

private struct SensorLinkRowLabel: View {
    let sensor: SensorConfig
    let zones: [ZoneConfig]

    private var linkedZoneName: String? {
        guard let zoneId = sensor.linkedZoneId else { return nil }
        return zones.first(where: { $0.id == zoneId })?.name
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 13))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 28, height: 28)
                .background(DS.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(sensor.displayName)
                    .font(DS.Font.cardTitle)
                if sensor.alias != nil && !sensor.alias!.isEmpty {
                    Text(sensor.name)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                if let zoneName = linkedZoneName {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(zoneName)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                } else {
                    Text("No zone linked")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }

            Spacer()

            if sensor.autoWaterEnabled {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.accent)
            }
        }
    }
}

// MARK: - Detail View

struct SensorLinkDetailView: View {
    let sensor: SensorConfig?
    let zones: [ZoneConfig]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var sensorAlias: String = ""
    @State private var selectedZoneId: String = ""
    @State private var threshold: Double = 30
    @State private var autoWaterEnabled: Bool = false
    @State private var isHiddenFromGraphs: Bool = false

    private var linkedZone: ZoneConfig? {
        guard !selectedZoneId.isEmpty else { return nil }
        return zones.first(where: { $0.id == selectedZoneId })
    }

    var body: some View {
        List {
            if let sensor {
                Section {
                    HStack {
                        Text("Alias")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        TextField("Enter alias", text: $sensorAlias)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                    HStack {
                        Text("Original Name")
                            .foregroundStyle(DS.Color.textTertiary)
                        Spacer()
                        Text(sensor.name)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    HStack {
                        Text("EUI")
                            .foregroundStyle(DS.Color.textTertiary)
                        Spacer()
                        Text(sensor.eui)
                            .font(DS.Font.mono)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                } header: { Text("Sensor") }
            }

            Section {
                Picker("Zone", selection: $selectedZoneId) {
                    Text("None").tag("")
                    ForEach(zones) { zone in
                        Text(zone.name).tag(zone.id)
                    }
                }
            } header: { Text("Linked Zone") }
                footer: { Text("This zone will be suggested when the sensor is dry.") }

            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack {
                        Text("Alert threshold")
                            .font(DS.Font.cardBody)
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("\(Int(threshold))%")
                            .font(DS.Font.cardTitle)
                            .foregroundStyle(DS.Color.moisture(threshold))
                    }
                    Slider(value: $threshold, in: 0...100, step: 1)
                        .tint(DS.Color.moisture(threshold))
                    DSMoistureBar(value: threshold)
                }
            } header: { Text("Moisture Threshold") }
             footer: { Text("You will be notified when soil moisture falls below this level.") }

            Section {
                Toggle("Auto-water when dry", isOn: $autoWaterEnabled)
                    .tint(DS.Color.accent)
                    .disabled(selectedZoneId.isEmpty)
                if autoWaterEnabled && !selectedZoneId.isEmpty {
                    DSInlineBanner(
                        message: "Zone \"\(linkedZone?.name ?? "")\" will start automatically when moisture drops below \(Int(threshold))%.",
                        style: .info
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                }
            } header: { Text("Automation") }

            Section {
                Toggle("Show in Graphs", isOn: Binding(
                    get: { !isHiddenFromGraphs },
                    set: { isHiddenFromGraphs = !$0 }
                ))
                .tint(DS.Color.accent)
            } header: { Text("Visibility") }
              footer: { Text("Hidden sensors are excluded from all graphs.") }

            if sensor?.linkedZoneId != nil {
                Section {
                    Button("Remove Link", role: .destructive) {
                        removeLink()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(sensor?.displayName ?? "Link")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let sensor {
                sensorAlias = sensor.alias ?? ""
                selectedZoneId = sensor.linkedZoneId ?? ""
                threshold = sensor.moistureThreshold ?? 30
                autoWaterEnabled = sensor.autoWaterEnabled
                isHiddenFromGraphs = sensor.isHiddenFromGraphs
            }
        }
        .onChange(of: sensorAlias) { saveChanges() }
        .onChange(of: selectedZoneId) { saveChanges() }
        .onChange(of: threshold) { saveChanges() }
        .onChange(of: autoWaterEnabled) { saveChanges() }
        .onChange(of: isHiddenFromGraphs) { saveChanges() }
    }

    private func saveChanges() {
        guard let sensor else { return }
        let trimmedAlias = sensorAlias.trimmingCharacters(in: .whitespaces)
        sensor.alias = trimmedAlias.isEmpty ? nil : trimmedAlias
        sensor.linkedZoneId = selectedZoneId.isEmpty ? nil : selectedZoneId
        sensor.moistureThreshold = threshold
        sensor.autoWaterEnabled = autoWaterEnabled
        sensor.isHiddenFromGraphs = isHiddenFromGraphs
        _ = try? modelContext.save()
    }

    private func removeLink() {
        guard sensor != nil else { return }
        selectedZoneId = ""
        autoWaterEnabled = false
        saveChanges()
        HapticFeedback.notification(.success)
        dismiss()
    }
}
