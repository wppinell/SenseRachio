import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        List {
            // App identity
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.accent.opacity(0.1))
                                .frame(width: 72, height: 72)
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(DS.Color.accent)
                        }
                        VStack(spacing: DS.Spacing.xs) {
                            Text("RachioSense")
                                .font(DS.Font.cardTitle)
                                .foregroundStyle(DS.Color.textPrimary)
                            Text("Version \(version)")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    .padding(.vertical, DS.Spacing.md)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Text("Version")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(version)
                        .foregroundStyle(DS.Color.textPrimary)
                        .font(DS.Font.mono)
                }
                HStack {
                    Text("Build")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(build)
                        .foregroundStyle(DS.Color.textPrimary)
                        .font(DS.Font.mono)
                }
                HStack {
                    Text("Copyright")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("© 2026 Pinello")
                        .foregroundStyle(DS.Color.textPrimary)
                }
            } header: { Text("Version Info") }

            Section {
                HStack {
                    Text("Framework")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("SwiftUI + SwiftData")
                        .foregroundStyle(DS.Color.textPrimary)
                }
                HStack {
                    Text("Minimum iOS")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("iOS 17.0")
                        .foregroundStyle(DS.Color.textPrimary)
                }
                HStack {
                    Text("Dependencies")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text("None (Apple frameworks only)")
                        .foregroundStyle(DS.Color.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
            } header: { Text("Technical") }

            Section {
                NavigationLink {
                    OpenSourceLicensesView()
                } label: {
                    DSSettingRow(
                        icon: "doc.text.fill",
                        iconColor: DS.Color.textSecondary,
                        title: "Open Source Licenses"
                    )
                }
            } header: { Text("Legal") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

}

// MARK: - Open Source Licenses

private struct OpenSourceLicensesView: View {
    var body: some View {
        List {
            Section {
                DSInlineBanner(
                    message: "RachioSense uses only Apple's built-in frameworks and has no third-party dependencies.",
                    style: .info
                )
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }

            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Apple Frameworks Used")
                        .font(DS.Font.cardTitle)
                    ForEach(["SwiftUI", "SwiftData", "BackgroundTasks", "UserNotifications", "Foundation", "Security"], id: \.self) { name in
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Color.online)
                            Text(name)
                                .font(DS.Font.cardBody)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
