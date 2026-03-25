import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppStorageKey.accentColor) private var accentColorName = "Blue"

    var accentColor: Color {
        DS.Color.accentOptions[accentColorName] ?? DS.Color.accent
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $appState.selectedTab) {
                DashboardView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(0)

                SensorsView()
                    .tabItem { Label("Sensors", systemImage: "leaf.fill") }
                    .tag(1)

                ZonesView()
                    .tabItem { Label("Zones", systemImage: "drop.fill") }
                    .tag(2)

                SettingsView(isOnboarding: false)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(3)
            }
            .tint(accentColor)

            if appState.showErrorBanner, let msg = appState.errorMessage {
                DSErrorBanner(message: msg, onDismiss: { appState.dismissError() })
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35), value: appState.showErrorBanner)
                    .zIndex(100)
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
