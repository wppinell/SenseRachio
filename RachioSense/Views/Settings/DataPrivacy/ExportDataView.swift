import SwiftUI
import SwiftData

struct ExportDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var readings: [SensorReading]
    @Query private var sensors: [SensorConfig]
    @AppStorage(AppStorageKey.exportFormat) private var format = "csv"
    @AppStorage(AppStorageKey.exportDateRange) private var dateRange = "30d"

    @State private var includeReadings = true
    @State private var includeSettings = false
    @State private var isExporting = false
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false
    @State private var exportError: String? = nil

    var body: some View {
        List {
            Section {
                Picker("Format", selection: $format) {
                    Text("CSV").tag("csv")
                    Text("JSON").tag("json")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: { Text("Format") }

            Section {
                Picker("Date Range", selection: $dateRange) {
                    Text("Last 7 days").tag("7d")
                    Text("Last 30 days").tag("30d")
                    Text("All data").tag("all")
                }
            } header: { Text("Date Range") }

            Section {
                Toggle("Sensor Readings", isOn: $includeReadings)
                    .tint(DS.Color.accent)
                Toggle("App Settings", isOn: $includeSettings)
                    .tint(DS.Color.accent)
            } header: { Text("Include") }
             footer: { Text("Credentials are never exported.") }

            if let error = exportError {
                Section {
                    DSInlineBanner(message: error, style: .error)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }
            }

            Section {
                if includeReadings {
                    HStack {
                        Text("Sensor readings")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("\(filteredReadings.count)")
                            .foregroundStyle(DS.Color.textPrimary)
                            .monospacedDigit()
                    }
                }
                if includeSettings {
                    HStack {
                        Text("Sensor configs")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("\(sensors.count)")
                            .foregroundStyle(DS.Color.textPrimary)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("App settings")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("\(appSettingsDict().count) keys")
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                }
            } header: { Text("Preview") }

            Section {
                Button {
                    Task { await generateExport() }
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView().scaleEffect(0.85)
                            Text("Generating…")
                        } else {
                            Label("Export Now", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(DS.Color.accent)
                .disabled(isExporting || (!includeReadings && !includeSettings))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var filteredReadings: [SensorReading] {
        let cutoff: Date
        switch dateRange {
        case "7d":  cutoff = Date().addingTimeInterval(-7 * 86400)
        case "30d": cutoff = Date().addingTimeInterval(-30 * 86400)
        default:    return readings
        }
        return readings.filter { $0.recordedAt >= cutoff }
    }

    private func generateExport() async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }

        do {
            let data: Data
            if format == "csv" {
                data = try generateCSV()
            } else {
                data = try generateJSON()
            }

            let fileName = "rachiosense_export_\(dateString()).\(format)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)
            exportURL = tempURL
            showShareSheet = true
            HapticFeedback.notification(.success)
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
            HapticFeedback.notification(.error)
        }
    }

    private func generateCSV() throws -> Data {
        var csv = ""
        if includeReadings {
            csv += "eui,moisture,temperature_c,recorded_at\n"
            for r in filteredReadings {
                let dateStr = ISO8601DateFormatter().string(from: r.recordedAt)
                csv += "\(r.eui),\(r.moisture),\(r.tempC),\(dateStr)\n"
            }
        }
        if includeSettings {
            csv += "\n# App Settings\nkey,value\n"
            for (key, value) in appSettingsDict() {
                csv += "\(key),\(value)\n"
            }
        }
        guard let data = csv.data(using: .utf8) else {
            throw NSError(domain: "Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV"])
        }
        return data
    }

    private func generateJSON() throws -> Data {
        var root: [String: Any] = [:]

        if includeReadings {
            root["sensor_readings"] = filteredReadings.map { r -> [String: Any] in
                [
                    "eui": r.eui,
                    "moisture": r.moisture,
                    "temperature_c": r.tempC,
                    "recorded_at": ISO8601DateFormatter().string(from: r.recordedAt)
                ]
            }
        }

        if includeSettings {
            root["app_settings"] = appSettingsDict()
            root["sensor_configs"] = sensors.map { s -> [String: Any] in
                var d: [String: Any] = [
                    "id": s.id,
                    "name": s.name,
                    "eui": s.eui,
                    "auto_water_enabled": s.autoWaterEnabled,
                    "is_hidden_from_graphs": s.isHiddenFromGraphs
                ]
                if let alias = s.alias { d["alias"] = alias }
                if let zoneId = s.linkedZoneId { d["linked_zone_id"] = zoneId }
                if let threshold = s.moistureThreshold { d["moisture_threshold"] = threshold }
                if let group = s.groupId { d["group_id"] = group }
                return d
            }
        }

        return try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted)
    }

    /// Collect all AppStorage settings (no credentials)
    private func appSettingsDict() -> [String: String] {
        let keys: [String] = [
            AppStorageKey.theme, AppStorageKey.accentColor,
            AppStorageKey.animationsEnabled, AppStorageKey.hapticsEnabled,
            AppStorageKey.temperatureUnit, AppStorageKey.moistureUnit,
            AppStorageKey.durationUnit, AppStorageKey.volumeUnit,
            AppStorageKey.dryThreshold, AppStorageKey.lowThreshold,
            AppStorageKey.autoWaterThreshold,
            AppStorageKey.foregroundRefresh, AppStorageKey.backgroundRefresh,
            AppStorageKey.dryAlertsEnabled, AppStorageKey.lowAlertsEnabled,
            AppStorageKey.sensorOfflineEnabled, AppStorageKey.zoneStartedEnabled,
            AppStorageKey.zoneStoppedEnabled, AppStorageKey.scheduleRunEnabled,
            AppStorageKey.dailySummaryEnabled, AppStorageKey.weeklyReportEnabled,
            AppStorageKey.historyRetention, AppStorageKey.exportFormat,
            AppStorageKey.trendChartPeriod, AppStorageKey.graphYMin,
            AppStorageKey.graphYMax, AppStorageKey.quickActionsOnCards,
            AppStorageKey.sensorPrimaryLabel, AppStorageKey.sensorSecondaryLabel,
            AppStorageKey.statusIndicatorStyle, AppStorageKey.sensorGrouping,
            AppStorageKey.zoneGrouping
        ]
        let defaults = UserDefaults.standard
        var result: [String: String] = [:]
        for key in keys {
            if let val = defaults.object(forKey: key) {
                result[key] = "\(val)"
            }
        }
        return result
    }

    private func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date())
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
