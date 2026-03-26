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
            if newPhase == .active {
                // Clear stale key from removed 2w feature
                UserDefaults.standard.removeObject(forKey: "lastExtendedFetchTimestamp")
            }
        }
    }
}
