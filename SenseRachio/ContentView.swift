import SwiftUI

// ContentView is the root entry point — the actual routing logic lives in SenseRachioApp.
// This file is kept for Xcode template compatibility and preview purposes.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.hasAnyCredentials {
            MainTabView()
        } else {
            SettingsView(isOnboarding: true)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
