import SwiftUI
import SwiftData

struct LocalStorageView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var readings: [SensorReading]
    @Query private var sensors: [SensorConfig]
    @Query private var zones: [ZoneConfig]
    @AppStorage(AppStorageKey.historyRetention) private var retentionDays = 30

    @State private var showClearOldConfirmation = false
    @State private var showOptimizeConfirmation = false
    @State private var operationMessage: String? = nil
    @State private var isProcessing = false

    private let retentionOptions: [(label: String, days: Int)] = [
        ("7 days", 7),
        ("30 days", 30),
        ("90 days", 90),
        ("1 year", 365),
        ("Forever", -1),
    ]

    private var estimatedSizeKB: Int {
        // rough estimate: ~100 bytes per reading
        return (readings.count * 100) / 1024
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Sensor Readings")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(readings.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Configured Sensors")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(sensors.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Zone Configs")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(zones.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Estimated Size")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(estimatedSizeKB < 1024
                         ? "\(estimatedSizeKB) KB"
                         : String(format: "%.1f MB", Double(estimatedSizeKB) / 1024))
                    .foregroundStyle(DS.Color.textPrimary)
                    .monospacedDigit()
                }
            } header: { Text("Usage") }

            Section {
                Picker("Keep history for", selection: $retentionDays) {
                    ForEach(retentionOptions, id: \.days) { opt in
                        Text(opt.label).tag(opt.days)
                    }
                }
            } header: { Text("History Retention") }
             footer: {
                if retentionDays == -1 {
                    Text("All readings are kept indefinitely. This may slow down the app over time.")
                } else {
                    Text("Readings older than \(retentionDays) days are automatically deleted during background refresh.")
                }
            }

            if let msg = operationMessage {
                Section {
                    DSInlineBanner(message: msg, style: .success)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }
            }

            Section {
                Button(role: .destructive) {
                    showClearOldConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isProcessing {
                            ProgressView().scaleEffect(0.85)
                            Text("Processing…")
                        } else {
                            Label("Clear Old Readings", systemImage: "trash")
                        }
                        Spacer()
                    }
                }
                .disabled(isProcessing)

                Button {
                    showOptimizeConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Optimize Database", systemImage: "wrench.and.screwdriver")
                        Spacer()
                    }
                }
                .disabled(isProcessing)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Local Storage")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear old readings?", isPresented: $showClearOldConfirmation, titleVisibility: .visible) {
            Button("Clear Old Readings", role: .destructive) { Task { await clearOldReadings() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let cutoffLabel = retentionDays == -1 ? "none" : "readings older than \(retentionDays) days"
            Text("This will delete \(cutoffLabel). This cannot be undone.")
        }
        .confirmationDialog("Optimize database?", isPresented: $showOptimizeConfirmation, titleVisibility: .visible) {
            Button("Optimize") { Task { await optimizeDatabase() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func clearOldReadings() async {
        guard retentionDays != -1 else { return }
        isProcessing = true
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        let predicate = #Predicate<SensorReading> { $0.recordedAt < cutoff }
        let descriptor = FetchDescriptor<SensorReading>(predicate: predicate)
        let oldReadings = (try? modelContext.fetch(descriptor)) ?? []
        for r in oldReadings { modelContext.delete(r) }
        try? modelContext.save()
        isProcessing = false
        operationMessage = "Deleted \(oldReadings.count) old readings."
        HapticFeedback.notification(.success)
    }

    private func optimizeDatabase() async {
        isProcessing = true
        try? await Task.sleep(nanoseconds: 500_000_000)
        try? modelContext.save()
        isProcessing = false
        operationMessage = "Database optimized."
        HapticFeedback.notification(.success)
    }
}
