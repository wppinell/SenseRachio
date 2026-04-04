import SwiftUI
import SwiftData

struct DiagnosticsView: View {
    @Query private var sensors: [SensorConfig]
    @Query private var zones: [ZoneConfig]
    @Query(sort: \SensorReading.recordedAt, order: .reverse) private var readings: [SensorReading]
    @EnvironmentObject private var appState: AppState

    @Environment(\.modelContext) private var modelContext
    @State private var scLatency: String = "—"
    @State private var rachioLatency: String = "—"
    @State private var isMeasuringLatency = false
    @State private var copySuccess = false


    // History API test
    @State private var historyTestResult: String = ""
    @State private var isTestingHistory = false
    @State private var historyTestStatus: HistoryTestStatus = .idle
    


    enum HistoryTestStatus {
        case idle, running, success, failure
        var color: Color {
            switch self {
            case .idle:    return DS.Color.textTertiary
            case .running: return DS.Color.warning
            case .success: return DS.Color.online
            case .failure: return DS.Color.error
            }
        }
    }

    private var lastSyncDate: String {
        guard let latest = readings.first else { return "Never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: latest.recordedAt, relativeTo: Date())
    }

    var body: some View {
        List {
            // API Latency
            Section {
                HStack {
                    Text("SenseCraft API")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(scLatency)
                        .foregroundStyle(latencyColor(scLatency))
                        .monospacedDigit()
                }
                HStack {
                    Text("Rachio API")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(rachioLatency)
                        .foregroundStyle(latencyColor(rachioLatency))
                        .monospacedDigit()
                }
                HStack {
                    Text("Weather API")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("—")
                        .foregroundStyle(DS.Color.textTertiary)
                }

                Button {
                    Task { await measureLatency() }
                } label: {
                    HStack {
                        Spacer()
                        if isMeasuringLatency {
                            ProgressView().scaleEffect(0.85)
                            Text("Measuring…")
                        } else {
                            Label("Measure Latency", systemImage: "speedometer")
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(DS.Color.accent)
                .disabled(isMeasuringLatency)
            } header: { Text("API Latency") }

            // Sync Status
            Section {
                HStack {
                    Text("Last Sync")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(lastSyncDate)
                        .foregroundStyle(DS.Color.textPrimary)
                }
                HStack {
                    Text("Sensors")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(sensors.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Zones")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(zones.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Readings Stored")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("\(readings.count)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .monospacedDigit()
                }
            } header: { Text("Sync Status") }

            // History API Test
            Section {
                Button {
                    Task { await testHistoryAPI() }
                } label: {
                    HStack {
                        Spacer()
                        if isTestingHistory {
                            ProgressView().scaleEffect(0.85)
                            Text("Testing…")
                        } else {
                            Label("Test History Endpoint", systemImage: "clock.arrow.circlepath")
                        }
                        Spacer()
                    }
                }
                .foregroundStyle(DS.Color.accent)
                .disabled(isTestingHistory || !appState.hasSenseCraftCredentials)

                if !historyTestResult.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack {
                            Circle()
                                .fill(historyTestStatus.color)
                                .frame(width: 8, height: 8)
                            Text(historyTestStatus == .success ? "Success" : historyTestStatus == .failure ? "Failed" : "Running")
                                .font(DS.Font.caption)
                                .foregroundStyle(historyTestStatus.color)
                                .bold()
                        }
                        ScrollView {
                            Text(historyTestResult)
                                .font(DS.Font.mono)
                                .foregroundStyle(DS.Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        
                        Button("Copy") {
                            UIPasteboard.general.string = historyTestResult
                            HapticFeedback.notification(.success)
                        }
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.accent)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            } header: { Text("History API Test") }
              footer: { Text("Tests /list_telemetry_data using first visible sensor. Check raw response to verify endpoint works.") }

            // App Info
            Section {
                HStack {
                    Text("App Version")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(DS.Color.textPrimary)
                        .font(DS.Font.mono)
                }
                HStack {
                    Text("iOS Version")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(UIDevice.current.systemVersion)
                        .foregroundStyle(DS.Color.textPrimary)
                        .font(DS.Font.mono)
                }
                HStack {
                    Text("Device")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(UIDevice.current.model)
                        .foregroundStyle(DS.Color.textPrimary)
                        .font(DS.Font.mono)
                }
                HStack {
                    Text("SenseCraft")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    DSBadge(
                        text: appState.hasSenseCraftCredentials ? "Connected" : "Not Connected",
                        color: appState.hasSenseCraftCredentials ? DS.Color.online : DS.Color.error,
                        small: true
                    )
                }
                HStack {
                    Text("Rachio")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    DSBadge(
                        text: appState.hasRachioCredentials ? "Connected" : "Not Connected",
                        color: appState.hasRachioCredentials ? DS.Color.online : DS.Color.error,
                        small: true
                    )
                }
            } header: { Text("App Info") }

            // Actions
            Section {
                Button {
                    copyDebugLog()
                } label: {
                    HStack {
                        Spacer()
                        if copySuccess {
                            Label("Copied!", systemImage: "checkmark")
                                .foregroundStyle(DS.Color.online)
                        } else {
                            Label("Copy Debug Log", systemImage: "doc.on.doc")
                                .foregroundStyle(DS.Color.accent)
                        }
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func latencyColor(_ text: String) -> Color {
        guard text != "—", let ms = Double(text.replacingOccurrences(of: " ms", with: "")) else {
            return DS.Color.textTertiary
        }
        if ms < 200 { return DS.Color.online }
        if ms < 600 { return DS.Color.warning }
        return DS.Color.error
    }

    private func testHistoryAPI() async {
        guard let sensor = sensors.first(where: { !$0.isHiddenFromGraphs }) ?? sensors.first else {
            historyTestResult = "No sensors available to test."
            historyTestStatus = .failure
            return
        }

        isTestingHistory = true
        historyTestStatus = .running
        historyTestResult = "Fetching 168h (7 day) history for: \(sensor.displayName) (\(sensor.eui))…\n(fetches in 24h chunks — may take a few seconds)"

        let start = Date()
        do {
            let history = try await SenseCraftAPI.shared.fetchHistory(eui: sensor.eui, hours: 168)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)

            if history.isEmpty {
                historyTestStatus = .failure
                historyTestResult = """
                ⚠️ 0 readings returned in \(elapsed)ms
                Sensor: \(sensor.displayName) (\(sensor.eui))
                """
            } else {
                historyTestStatus = .success
                let sorted = history.sorted { $0.timestamp < $1.timestamp }
                let first = sorted.first!
                let last = sorted.last!
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short

                // First 100 readings as log lines
                let sample = sorted.prefix(100).map { r in
                    "\(formatter.string(from: r.timestamp)): \(r.moisture.map { String(format: "%.1f%%", $0) } ?? "nil") / \(r.tempC.map { String(format: "%.1fC", $0) } ?? "nil")"
                }.joined(separator: "\n")

                historyTestResult = """
                ✅ \(history.count) readings in \(elapsed)ms
                Sensor: \(sensor.displayName) (\(sensor.eui))
                Range: \(formatter.string(from: first.timestamp)) → \(formatter.string(from: last.timestamp))

                First 100 readings:
                \(sample)
                """
            }
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            historyTestStatus = .failure
            historyTestResult = """
            ❌ Error after \(elapsed)ms
            Sensor: \(sensor.displayName) (\(sensor.eui))
            Error: \(error.localizedDescription)
            """
        }

        isTestingHistory = false
    }

    private func measureLatency() async {
        isMeasuringLatency = true
        defer { isMeasuringLatency = false }

        // Measure SenseCraft
        if appState.hasSenseCraftCredentials {
            let start = Date()
            _ = try? await SenseCraftAPI.shared.listDevices()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            await MainActor.run { scLatency = "\(ms) ms" }
        }

        // Measure Rachio
        if appState.hasRachioCredentials {
            let start = Date()
            _ = try? await RachioAPI.shared.getDevices()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            await MainActor.run { rachioLatency = "\(ms) ms" }
        }
    }

    private func copyDebugLog() {
        let log = """
        RachioSense Diagnostic Report
        ==============================
        Date: \(Date())
        App Version: \(appVersion)
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)

        Connections:
        - SenseCraft: \(appState.hasSenseCraftCredentials ? "Connected" : "Not Connected")
        - Rachio: \(appState.hasRachioCredentials ? "Connected" : "Not Connected")

        Data:
        - Sensors: \(sensors.count)
        - Zones: \(zones.count)
        - Readings: \(readings.count)
        - Last Sync: \(lastSyncDate)

        Latency:
        - SenseCraft: \(scLatency)
        - Rachio: \(rachioLatency)
        """
        UIPasteboard.general.string = log
        HapticFeedback.notification(.success)
        copySuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copySuccess = false
        }
    }
}
