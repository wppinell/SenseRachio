import SwiftUI
import UserNotifications

struct PrivacyView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppStorageKey.analyticsEnabled) private var analyticsEnabled = false
    @AppStorage(AppStorageKey.crashReportsEnabled) private var crashReports = false
    @Environment(\.modelContext) private var modelContext

    @State private var notificationStatus: String = "Checking…"
    @State private var backgroundRefreshStatus: String = "Checking…"
    @State private var showDeleteConfirmation = false
    @State private var showExportConfirmation = false

    var body: some View {
        List {
            // Permissions
            Section {
                HStack {
                    Text("Location")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("Not Required")
                        .foregroundStyle(DS.Color.online)
                        .font(DS.Font.caption)
                }

                HStack {
                    Text("Notifications")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(notificationStatus)
                        .foregroundStyle(notificationStatusColor)
                        .font(DS.Font.caption)
                }

                HStack {
                    Text("Background Refresh")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(backgroundRefreshStatus)
                        .foregroundStyle(backgroundRefreshStatusColor)
                        .font(DS.Font.caption)
                }

                Button("Manage Permissions in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(DS.Color.accent)
            } header: { Text("Permissions") }

            // Data Collection
            Section {
                Toggle("Analytics", isOn: $analyticsEnabled)
                    .tint(DS.Color.accent)
                Toggle("Crash Reports", isOn: $crashReports)
                    .tint(DS.Color.accent)
            } header: { Text("Data Collection") }
             footer: { Text("Analytics and crash reports help us improve the app. All data is anonymized. No personal information or credentials are ever shared.") }

            // Delete My Data
            Section {
                Button {
                    showExportConfirmation = true
                } label: {
                    Label("Request Data Export", systemImage: "square.and.arrow.up")
                        .foregroundStyle(DS.Color.accent)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All My Data", systemImage: "trash.fill")
                }
            } header: { Text("Delete My Data") }
             footer: { Text("Deleting all data will remove all sensor configs, readings, zone configs, groups, and credentials from this device.") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkPermissions() }
        .confirmationDialog("Delete all data?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all stored data and credentials. This cannot be undone.")
        }
    }

    private func checkPermissions() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus == .authorized ? "Allowed" : "Not Allowed"
            let bgStatus = UIApplication.shared.backgroundRefreshStatus
            backgroundRefreshStatus = bgStatus == .available ? "Enabled" : "Disabled"
        }
    }

    private var notificationStatusColor: Color {
        notificationStatus == "Allowed" ? DS.Color.online : DS.Color.error
    }

    private var backgroundRefreshStatusColor: Color {
        backgroundRefreshStatus == "Enabled" ? DS.Color.online : DS.Color.warning
    }

    private func deleteAllData() {
        appState.clearAll()
        try? modelContext.delete(model: SensorConfig.self)
        try? modelContext.delete(model: ZoneConfig.self)
        try? modelContext.delete(model: SensorReading.self)
        try? modelContext.delete(model: SensorGroup.self)
        try? modelContext.save()
        HapticFeedback.notification(.success)
    }
}
