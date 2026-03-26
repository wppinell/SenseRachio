import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sensors: [SensorConfig]
    @Query private var zones: [ZoneConfig]
    @Query private var groups: [ZoneGroup]

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showFilePicker = false
    @State private var statusMessage: String? = nil
    @State private var statusIsError = false
    @State private var backupURL: URL? = nil
    @State private var showShareSheet = false
    @State private var showRestoreConfirm = false
    @State private var pendingRestoreURL: URL? = nil

    var body: some View {
        List {
            // Backup
            Section {
                HStack {
                    Text("Sensors configured")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(sensors.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Zone groups")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(groups.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                Button {
                    Task { await createBackup() }
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView().scaleEffect(0.85)
                            Text("Creating backup…")
                        } else {
                            Label("Create Backup", systemImage: "arrow.up.doc")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(DS.Color.accent)
                .disabled(isExporting)
            } header: { Text("Backup") }
              footer: { Text("Exports sensor aliases, zone links, thresholds, groups, and display settings. Credentials are never included.") }

            // Restore
            Section {
                Button {
                    showFilePicker = true
                } label: {
                    HStack {
                        Spacer()
                        if isImporting {
                            ProgressView().scaleEffect(0.85)
                            Text("Restoring…")
                        } else {
                            Label("Restore from Backup", systemImage: "arrow.down.doc")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(DS.Color.accent)
                .disabled(isImporting)
            } header: { Text("Restore") }
              footer: { Text("Restores sensor aliases, links, thresholds, and groups. Does not affect credentials or stored readings.") }

            // Status
            if let msg = statusMessage {
                Section {
                    DSInlineBanner(message: msg, style: statusIsError ? .error : .success)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = backupURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    pendingRestoreURL = url
                    showRestoreConfirm = true
                }
            case .failure(let error):
                statusMessage = "Could not open file: \(error.localizedDescription)"
                statusIsError = true
            }
        }
        .confirmationDialog("Restore Settings?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let url = pendingRestoreURL {
                    Task { await restoreBackup(from: url) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite sensor aliases, links, thresholds, and groups. Credentials and readings are not affected.")
        }
    }

    // MARK: - Backup

    private func createBackup() async {
        isExporting = true
        defer { isExporting = false }

        let sensorBackups = sensors.map { s in
            [
                "id": s.id,
                "name": s.name,
                "eui": s.eui,
                "alias": s.alias ?? "",
                "linkedZoneId": s.linkedZoneId ?? "",
                "autoWaterEnabled": s.autoWaterEnabled,
                "isHiddenFromGraphs": s.isHiddenFromGraphs
            ] as [String: Any]
        }

        let groupBackups = groups.map { g in
            [
                "id": g.id,
                "name": g.name,
                "sortOrder": g.sortOrder,
                "assignedZoneIds": g.assignedZoneIds
            ] as [String: Any]
        }

        // AppStorage settings
        let defaults = UserDefaults.standard
        let settings: [String: Any] = [
            AppStorageKey.trendChartPeriod:        defaults.string(forKey: AppStorageKey.trendChartPeriod) ?? "24h",
            AppStorageKey.graphYMin:               defaults.double(forKey: AppStorageKey.graphYMin) == 0 ? 15.0 : defaults.double(forKey: AppStorageKey.graphYMin),
            AppStorageKey.graphYMax:               defaults.double(forKey: AppStorageKey.graphYMax) == 0 ? 45.0 : defaults.double(forKey: AppStorageKey.graphYMax),
            AppStorageKey.temperatureUnit:         defaults.string(forKey: AppStorageKey.temperatureUnit) ?? "fahrenheit",
            AppStorageKey.theme:                   defaults.string(forKey: AppStorageKey.theme) ?? "system",
        ]

        let payload: [String: Any] = [
            "version": 1,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "sensors": sensorBackups,
            "groups": groupBackups,
            "settings": settings
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"
            let fileName = "rachiosense_backup_\(f.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url)
            backupURL = url
            showShareSheet = true
            HapticFeedback.notification(.success)
        } catch {
            statusMessage = "Backup failed: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    // MARK: - Restore

    private func restoreBackup(from url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "Restore", code: 0, userInfo: [NSLocalizedDescriptionKey: "Permission denied to read file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "Restore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid backup file format."])
            }

            var restoredSensors = 0
            var restoredGroups = 0

            // Restore sensor configs
            if let sensorBackups = json["sensors"] as? [[String: Any]] {
                for backup in sensorBackups {
                    guard let eui = backup["eui"] as? String else { continue }
                    // Find existing sensor by EUI
                    if let existing = sensors.first(where: { $0.eui == eui }) {
                        existing.alias = (backup["alias"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        existing.linkedZoneId = (backup["linkedZoneId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        // moistureThreshold removed — now using global thresholds
                        existing.autoWaterEnabled = backup["autoWaterEnabled"] as? Bool ?? false
                        existing.isHiddenFromGraphs = backup["isHiddenFromGraphs"] as? Bool ?? false
                        restoredSensors += 1
                    }
                }
            }

            // Restore groups — delete existing, re-create
            if let groupBackups = json["groups"] as? [[String: Any]] {
                for g in groups { modelContext.delete(g) }
                for backup in groupBackups {
                    guard let id = backup["id"] as? String,
                          let name = backup["name"] as? String else { continue }
                    let group = ZoneGroup(id: id, name: name)
                    group.sortOrder = backup["sortOrder"] as? Int ?? 0
                    group.assignedZoneIds = backup["assignedZoneIds"] as? [String] ?? []
                    modelContext.insert(group)
                    restoredGroups += 1
                }
            }

            // Restore settings
            if let settings = json["settings"] as? [String: Any] {
                let defaults = UserDefaults.standard
                for (key, value) in settings {
                    if let s = value as? String { defaults.set(s, forKey: key) }
                    else if let d = value as? Double { defaults.set(d, forKey: key) }
                    else if let b = value as? Bool { defaults.set(b, forKey: key) }
                }
            }

            _ = try? modelContext.save()
            HapticFeedback.notification(.success)
            statusIsError = false
            statusMessage = "✅ Restored \(restoredSensors) sensors, \(restoredGroups) groups."

        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
            statusIsError = true
            HapticFeedback.notification(.error)
        }
    }
}
