import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    // Alerts
    @AppStorage(AppStorageKey.dryAlertsEnabled) private var dryAlerts = true
    @AppStorage(AppStorageKey.lowAlertsEnabled) private var lowAlerts = true
    @AppStorage(AppStorageKey.sensorOfflineEnabled) private var sensorOffline = true

    // Zone Activity
    @AppStorage(AppStorageKey.zoneStartedEnabled) private var zoneStarted = false
    @AppStorage(AppStorageKey.zoneStoppedEnabled) private var zoneStopped = false
    @AppStorage(AppStorageKey.scheduleRunEnabled) private var scheduleRun = false

    // Summaries
    @AppStorage(AppStorageKey.dailySummaryEnabled) private var dailySummary = false
    @AppStorage(AppStorageKey.dailySummaryHour) private var dailySummaryHour = 8
    @AppStorage(AppStorageKey.dailySummaryMinute) private var dailySummaryMinute = 0
    @AppStorage(AppStorageKey.weeklyReportEnabled) private var weeklyReport = false
    @AppStorage(AppStorageKey.weeklyReportDay) private var weeklyReportDay = 1

    // Quiet Hours
    @AppStorage(AppStorageKey.quietHoursEnabled) private var quietHours = false
    @AppStorage(AppStorageKey.quietHoursStartHour) private var quietStart = 22
    @AppStorage(AppStorageKey.quietHoursEndHour) private var quietEnd = 7

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
                Toggle("Dry Alerts", isOn: $dryAlerts)
                    .tint(DS.Color.error)
                Toggle("Low Alerts", isOn: $lowAlerts)
                    .tint(DS.Color.warning)
                Toggle("Sensor Offline", isOn: $sensorOffline)
                    .tint(DS.Color.textSecondary)
            } header: { Text("Sensor Alerts") }
             footer: { Text("Alerts fire when soil moisture reaches the configured threshold levels.") }

            // Zone Activity
            Section {
                Toggle("Zone Started", isOn: $zoneStarted)
                    .tint(DS.Color.online)
                Toggle("Zone Stopped", isOn: $zoneStopped)
                    .tint(DS.Color.accent)
                Toggle("Scheduled Run", isOn: $scheduleRun)
                    .tint(DS.Color.accent)
            } header: { Text("Zone Activity") }

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

            // Quiet Hours
            Section {
                Toggle("Quiet Hours", isOn: $quietHours)
                    .tint(DS.Color.accent)

                if quietHours {
                    HStack {
                        Text("From")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Picker("Start", selection: $quietStart) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("Until")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Picker("End", selection: $quietEnd) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            } header: { Text("Quiet Hours") }
             footer: {
                if quietHours {
                    Text("Notifications will be silenced from \(hourLabel(quietStart)) to \(hourLabel(quietEnd)).")
                }
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

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        let date = Calendar.current.date(from: comps) ?? Date()
        return formatter.string(from: date)
    }
}
