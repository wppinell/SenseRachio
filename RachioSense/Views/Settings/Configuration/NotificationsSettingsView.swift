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
