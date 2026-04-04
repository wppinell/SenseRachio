import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

@main
struct RachioSenseApp: App {
    let modelContainer: ModelContainer
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            modelContainer = try ModelContainer(for: SensorConfig.self, ZoneConfig.self, SensorReading.self,
                                                    ZoneGroup.self, DashboardCardOrder.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        BackgroundRefreshManager.shared.registerTasks()
        BackgroundRefreshManager.shared.scheduleAppRefresh()
    }

    var body: some Scene {
        WindowGroup {
            if appState.hasAnyCredentials {
                MainTabView()
                    .environmentObject(appState)
            } else {
                SettingsView(isOnboarding: true)
                    .environmentObject(appState)
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Clear stale key from removed 2w feature
                UserDefaults.standard.removeObject(forKey: "lastExtendedFetchTimestamp")
                // Request notification permission on every foreground (no-op if already granted/denied)
                Task { await NotificationService.shared.requestPermission() }
            case .background:
                // Re-submit background refresh request each time we background
                // (iOS may have dropped the pending request while the app was active)
                BackgroundRefreshManager.shared.scheduleAppRefresh()
            default:
                break
            }
        }
    }
}
