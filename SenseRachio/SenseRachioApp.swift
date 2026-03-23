import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

@main
struct SenseRachioApp: App {
    let modelContainer: ModelContainer
    @StateObject private var appState = AppState()

    init() {
        do {
            modelContainer = try ModelContainer(for: SensorConfig.self, ZoneConfig.self, SensorReading.self)
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
    }
}
