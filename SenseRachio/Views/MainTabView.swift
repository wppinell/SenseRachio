import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppStorageKey.accentColor) private var accentColorName = "Blue"

    var accentColor: Color {
        DS.Color.accentOptions[accentColorName] ?? DS.Color.accent
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                SensorsView()
                    .tabItem { Label("Sensors", systemImage: "sensor.fill") }

                ZonesView()
                    .tabItem { Label("Zones", systemImage: "drop.fill") }

                SettingsView(isOnboarding: false)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
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
