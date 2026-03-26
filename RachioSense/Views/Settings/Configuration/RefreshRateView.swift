import SwiftUI

struct RefreshRateView: View {
    @AppStorage(AppStorageKey.foregroundRefresh) private var foreground = 30
    @AppStorage(AppStorageKey.backgroundRefresh) private var background = 600
    @AppStorage(AppStorageKey.pushNotificationsEnabled) private var pushEnabled = true

    private let foregroundOptions: [(label: String, seconds: Int)] = [
        ("15 seconds", 15),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
    ]

    private let backgroundOptions: [(label: String, seconds: Int)] = [
        ("10 minutes", 600),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600),
    ]

    var body: some View {
        List {
            Section {
                DSInlineBanner(
                    message: "More frequent polling uses more battery. 30s foreground and 15m background are recommended.",
                    style: .info
                )
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }

            Section {
                Picker("When app is open", selection: $foreground) {
                    ForEach(foregroundOptions, id: \.seconds) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
            } header: { Text("Foreground Refresh") }
             footer: { Text("How often to refresh sensor data while the app is open.") }

            Section {
                Picker("When app is in background", selection: $background) {
                    ForEach(backgroundOptions, id: \.seconds) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
            } header: { Text("Background Refresh") }
             footer: { Text("iOS may override this based on system conditions and battery optimization.") }

            Section {
                Toggle("Push Notifications", isOn: $pushEnabled)
                    .tint(DS.Color.accent)
            } header: { Text("Push Notifications") }
             footer: { Text("Use push notifications instead of polling in the background. Requires notification permissions.") }

            Section {
                HStack {
                    Text("Estimated daily API calls")
                    Spacer()
                    Text(estimatedDailyCalls)
                        .foregroundStyle(DS.Color.textSecondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Battery impact")
                    Spacer()
                    Text(batteryImpact)
                        .foregroundStyle(batteryColor)
                }
            } header: { Text("Estimates") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Refresh Rate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var estimatedDailyCalls: String {
        let fgCalls = (16 * 3600) / foreground  // ~16 active hours/day
        let bgCalls = (8 * 3600) / background   // ~8 bg hours/day
        return "\(fgCalls + bgCalls)"
    }

    private var batteryImpact: String {
        if foreground <= 15 { return "High" }
        if foreground <= 30 { return "Moderate" }
        return "Low"
    }

    private var batteryColor: Color {
        if foreground <= 15 { return DS.Color.error }
        if foreground <= 30 { return DS.Color.warning }
        return DS.Color.online
    }
}
