import SwiftUI
import SwiftData

struct SettingsView: View {
    let isOnboarding: Bool
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if isOnboarding {
            NavigationStack {
                OnboardingView()
                    .environmentObject(appState)
            }
        } else {
            NavigationStack {
                settingsList
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var settingsList: some View {
        List {
            // MARK: ACCOUNT
            Section {
                NavigationLink {
                    AccountSenseCraftView()
                        .environmentObject(appState)
                } label: {
                    DSSettingRow(
                        icon: "sensor.fill",
                        iconColor: Color(hex: "00B298"),
                        title: "SenseCraft",
                        value: appState.hasSenseCraftCredentials ? "Connected" : "Not Connected"
                    )
                }

                NavigationLink {
                    AccountRachioView()
                        .environmentObject(appState)
                } label: {
                    DSSettingRow(
                        icon: "drop.fill",
                        iconColor: Color(hex: "0066CC"),
                        title: "Rachio",
                        value: appState.hasRachioCredentials ? "Connected" : "Not Connected"
                    )
                }
            } header: { Text("Account") }

            // MARK: CONFIGURATION
            Section {
                NavigationLink {
                    SensorZoneLinksView()
                } label: {
                    DSSettingRow(icon: "link", iconColor: DS.Color.accent, title: "Sensor-Zone Links")
                }

                NavigationLink {
                    ThresholdsView()
                } label: {
                    DSSettingRow(icon: "gauge.with.dots.needle.33percent", iconColor: DS.Color.warning, title: "Thresholds")
                }

                NavigationLink {
                    NotificationsSettingsView()
                } label: {
                    DSSettingRow(icon: "bell.fill", iconColor: DS.Color.error, title: "Notifications")
                }

                NavigationLink {
                    GroupingView()
                } label: {
                    DSSettingRow(icon: "rectangle.3.group.fill", iconColor: Color(hex: "8B5CF6"), title: "Grouping")
                }

                NavigationLink {
                    RefreshRateView()
                } label: {
                    DSSettingRow(icon: "arrow.clockwise", iconColor: Color(hex: "16A34A"), title: "Refresh Rate")
                }

                NavigationLink {
                    WeatherIntegrationView()
                } label: {
                    DSSettingRow(icon: "cloud.sun.fill", iconColor: Color(hex: "F59E0B"), title: "Weather Integration")
                }
            } header: { Text("Configuration") }

            // MARK: DISPLAY
            Section {
                NavigationLink {
                    AppearanceView()
                } label: {
                    DSSettingRow(icon: "paintbrush.fill", iconColor: Color(hex: "EC4899"), title: "Appearance")
                }

                NavigationLink {
                    UnitsView()
                } label: {
                    DSSettingRow(icon: "ruler.fill", iconColor: Color(hex: "6366F1"), title: "Units")
                }

                NavigationLink {
                    DashboardLayoutView()
                } label: {
                    DSSettingRow(icon: "rectangle.grid.2x2.fill", iconColor: DS.Color.accent, title: "Dashboard Layout")
                }

                NavigationLink {
                    SensorLabelsView()
                } label: {
                    DSSettingRow(icon: "tag.fill", iconColor: Color(hex: "0891B2"), title: "Sensor Labels")
                }
            } header: { Text("Display") }

            // MARK: DATA & PRIVACY
            Section {
                NavigationLink {
                    LocalStorageView()
                } label: {
                    DSSettingRow(icon: "internaldrive.fill", iconColor: Color(hex: "374151"), title: "Local Storage")
                }

                NavigationLink {
                    BackupRestoreView()
                } label: {
                    DSSettingRow(icon: "externaldrive.fill.badge.checkmark", iconColor: Color(hex: "7C3AED"), title: "Backup & Restore")
                }

                NavigationLink {
                    ExportDataView()
                } label: {
                    DSSettingRow(icon: "square.and.arrow.up.fill", iconColor: Color(hex: "059669"), title: "Export Data")
                }

                NavigationLink {
                    PrivacyView()
                } label: {
                    DSSettingRow(icon: "lock.shield.fill", iconColor: Color(hex: "1D4ED8"), title: "Privacy")
                }
            } header: { Text("Data & Privacy") }

            // MARK: SUPPORT
            Section {
                NavigationLink {
                    HelpFAQView()
                } label: {
                    DSSettingRow(icon: "questionmark.circle.fill", iconColor: Color(hex: "0284C7"), title: "Help & FAQ")
                }

                NavigationLink {
                    ContactSupportView()
                } label: {
                    DSSettingRow(icon: "envelope.fill", iconColor: Color(hex: "7C3AED"), title: "Contact Support")
                }

                NavigationLink {
                    DiagnosticsView()
                } label: {
                    DSSettingRow(icon: "stethoscope", iconColor: Color(hex: "DC2626"), title: "Diagnostics")
                }

                NavigationLink {
                    AboutView()
                } label: {
                    DSSettingRow(icon: "info.circle.fill", iconColor: DS.Color.textSecondary, title: "About")
                }
            } header: { Text("Support") }

            // MARK: RESET
            Section {
                NavigationLink {
                    ResetView()
                        .environmentObject(appState)
                } label: {
                    DSSettingRow(icon: "arrow.counterclockwise", iconColor: DS.Color.error, title: "Reset")
                }
            } header: { Text("Reset") }
        }
        .listStyle(.insetGrouped)
    }
}

#Preview {
    SettingsView(isOnboarding: false)
        .environmentObject(AppState())
}
