import SwiftUI
import SwiftData

struct DiagnosticsView: View {
    @Query private var sensors: [SensorConfig]
    @Query private var zones: [ZoneConfig]
    @Query(sort: \SensorReading.recordedAt, order: .reverse) private var readings: [SensorReading]
    @EnvironmentObject private var appState: AppState

    @State private var scLatency: String = "—"
    @State private var rachioLatency: String = "—"
    @State private var isMeasuringLatency = false
    @State private var copySuccess = false

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
