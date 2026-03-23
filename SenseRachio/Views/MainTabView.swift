import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }

            if appState.hasSenseCraftCredentials {
                SensorsView()
                    .tabItem {
                        Label("Sensors", systemImage: "sensor.fill")
                    }
            }

            if appState.hasRachioCredentials {
                ZonesView()
                    .tabItem {
                        Label("Zones", systemImage: "drop.fill")
                    }
            }

            SettingsView(isOnboarding: false)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .overlay(alignment: .top) {
            if appState.showErrorBanner, let message = appState.errorMessage {
                ErrorBannerView(message: message) {
                    appState.dismissError()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: appState.showErrorBanner)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Error Banner

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .font(.footnote.bold())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .shadow(radius: 4)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
