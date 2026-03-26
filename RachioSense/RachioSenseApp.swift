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
                Task { await prefetchGraphData() }
            }
        }
    }
    
    /// Pre-fetch graph data on app launch (background thread)
    @MainActor
    private func prefetchGraphData() async {
        guard appState.hasSenseCraftCredentials else { return }
        
        let context = modelContainer.mainContext
        let prefetcher = GraphDataPrefetcher.shared
        await prefetcher.fetchIfNeeded(modelContext: context)
    }
}
