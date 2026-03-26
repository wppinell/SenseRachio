import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentPage = 0

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                // Hero
                VStack(spacing: DS.Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.accent.opacity(0.1))
                            .frame(width: 100, height: 100)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(DS.Color.accent)
                    }
                    VStack(spacing: DS.Spacing.sm) {
                        Text("Welcome to RachioSense")
                            .font(DS.Font.pageTitle)
                            .foregroundStyle(DS.Color.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("Connect your soil sensors and irrigation system to monitor and automate your garden.")
                            .font(DS.Font.cardBody)
                            .foregroundStyle(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.xl)

                // Service cards
                VStack(spacing: DS.Spacing.md) {
                    NavigationLink {
                        AccountSenseCraftView()
                            .environmentObject(appState)
                    } label: {
                        OnboardingServiceCard(
                            icon: "sensor.fill",
                            iconColor: Color(hex: "00B298"),
                            title: "SenseCraft",
                            subtitle: "Connect Seeed soil moisture sensors",
                            isConnected: appState.hasSenseCraftCredentials
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AccountRachioView()
                            .environmentObject(appState)
                    } label: {
                        OnboardingServiceCard(
                            icon: "drop.fill",
                            iconColor: Color(hex: "0066CC"),
                            title: "Rachio",
                            subtitle: "Connect smart irrigation controller",
                            isConnected: appState.hasRachioCredentials
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DS.Spacing.lg)

                if appState.hasAnyCredentials {
                    DSInlineBanner(
                        message: "You're connected! You can now use the app.",
                        style: .success
                    )
                    .padding(.horizontal, DS.Spacing.lg)
                }

                Spacer(minLength: DS.Spacing.xxl)
            }
        }
        .dsBackground()
        .navigationTitle("Get Started")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OnboardingServiceCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Spacer()

            if isConnected {
                DSBadge(text: "Connected", color: DS.Color.online, small: true)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard()
    }
}
