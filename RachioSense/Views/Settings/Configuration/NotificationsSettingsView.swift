import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    // Alerts
    @AppStorage(AppStorageKey.dryAlertsEnabled) private var dryAlerts = true
    @AppStorage(AppStorageKey.lowAlertsEnabled) private var lowAlerts = true
    @AppStorage(AppStorageKey.sensorOfflineEnabled) private var sensorOffline = true
    @AppStorage(AppStorageKey.predictiveAlertEnabled) private var predictiveAlerts = true
    @AppStorage(AppStorageKey.predictiveAlertWindowHours) private var predictiveWindow = 6
    @AppStorage(AppStorageKey.notificationCooldownHours) private var cooldownHours = 4

    // Zone Activity
    @AppStorage(AppStorageKey.zoneStoppedEnabled) private var zoneStopped = false
    @AppStorage(AppStorageKey.scheduleRunEnabled) private var scheduleRun = false
    @AppStorage(AppStorageKey.zoneSkipEnabled) private var zoneSkip = true

    // Service Alerts
    @AppStorage(AppStorageKey.serviceAlertsEnabled) private var serviceAlerts = true

    // Summaries
    @AppStorage(AppStorageKey.dailySummaryEnabled) private var dailySummary = false
    @AppStorage(AppStorageKey.dailySummaryHour) private var dailySummaryHour = 8
    @AppStorage(AppStorageKey.dailySummaryMinute) private var dailySummaryMinute = 0
    @AppStorage(AppStorageKey.weeklyReportEnabled) private var weeklyReport = false
    @AppStorage(AppStorageKey.weeklyReportDay) private var weeklyReportDay = 1

    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var showRequestPermission = false

    private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        List {
            // Permission status
            if permissionStatus != .authorized {
                Section {
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(DS.Color.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications Disabled")
                                .font(DS.Font.cardTitle)
                            Text("Enable notifications in iOS Settings to receive alerts.")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        Spacer()
                        Button("Enable") {
                            openSettings()
                        }
                        .buttonStyle(.bordered)
                        .tint(DS.Color.accent)
                        .controlSize(.small)
                    }
                }
                .listRowBackground(DS.Color.warningMuted)
            }

            // Alerts
            Section {
                Toggle("Critical Alerts", isOn: $dryAlerts)
                    .tint(DS.Color.error)
                Toggle("Low Alerts", isOn: $lowAlerts)
                    .tint(DS.Color.warning)
                Toggle("Sensor Offline", isOn: $sensorOffline)
                    .tint(DS.Color.textSecondary)
                Toggle("Predictive Alerts", isOn: $predictiveAlerts)
                    .tint(DS.Color.accent)
                if predictiveAlerts {
                    Picker("Alert window", selection: $predictiveWindow) {
                        Text("2 hours").tag(2)
                        Text("4 hours").tag(4)
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                    }
                    .foregroundStyle(DS.Color.textSecondary)
                }
            } header: { Text("Sensor Alerts") }
             footer: { Text("Critical and Low alerts fire when moisture has already crossed a threshold. Predictive alerts warn you ahead of time when a sensor is trending toward critical or dry.") }

            // Cooldown
            Section {
                Picker("Alert cooldown", selection: $cooldownHours) {
                    Text("2 hours").tag(2)
                    Text("4 hours").tag(4)
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                }
            } header: { Text("Cooldown") }
             footer: { Text("Minimum time between repeated alerts for the same sensor. Prevents notification spam when moisture stays low for extended periods.") }

            // Zone Activity
            Section {
                Toggle("Zone Stopped", isOn: $zoneStopped)
                    .tint(DS.Color.accent)
                Toggle("Scheduled Run", isOn: $scheduleRun)
                    .tint(DS.Color.accent)
                Toggle("Zone Skipped", isOn: $zoneSkip)
                    .tint(DS.Color.warning)
            } header: { Text("Zone Activity") }
             footer: { Text("Zone Skipped fires when Rachio's Weather Intelligence skips a scheduled run due to rain, freeze, or wind.") }

            // Service Alerts
            Section {
                Toggle("Service Disconnected", isOn: $serviceAlerts)
                    .tint(DS.Color.error)
            } header: { Text("Service Alerts") }
             footer: { Text("Alerts you when RachioSense hasn't been able to reach SenseCraft or Rachio for over 2 hours. Useful for catching credential expiry or network outages.") }

            // Summaries
            Section {
                Toggle("Daily Summary", isOn: $dailySummary)
                    .tint(DS.Color.accent)

                if dailySummary {
                    HStack {
                        Text("Time")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Picker("Hour", selection: $dailySummaryHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 60)
                        .clipped()
                        Text(":")
                        Picker("Minute", selection: $dailySummaryMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 60)
                        .clipped()
                    }
                    .frame(height: 80)
                }

                Toggle("Weekly Report", isOn: $weeklyReport)
                    .tint(DS.Color.accent)

                if weeklyReport {
                    Picker("Day", selection: $weeklyReportDay) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(weekdays[i]).tag(i)
                        }
                    }
                }
            } header: { Text("Summaries") }

            // Focus / Sleep Info
            Section {
                Label {
                    Text("RachioSense uses iOS Focus modes to manage quiet hours. Critical alerts are marked as Time Sensitive and can break through Sleep Focus if you allow them.")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                } icon: {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(DS.Color.accent)
                }

                Button("Open Focus Settings") {
                    openSettings()
                }
            } header: { Text("Sleep & Focus") }
              footer: {
                Text("To configure which alerts break through Sleep, go to Settings → Focus → Sleep → Apps → RachioSense.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkPermission() }
    }

    private func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { permissionStatus = settings.authorizationStatus }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
