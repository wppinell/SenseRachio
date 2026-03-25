import SwiftUI

struct ContactSupportView: View {
    var body: some View {
        List {
            Section {
                DSInlineBanner(
                    message: "SenseRachio is an open-source community project. Support is provided on a best-effort basis.",
                    style: .info
                )
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }

            Section {
                Link(destination: URL(string: "https://github.com/")!) {
                    HStack {
                        DSSettingRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            iconColor: Color(hex: "374151"),
                            title: "GitHub Issues",
                            value: "Report a bug"
                        )
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .foregroundStyle(DS.Color.textPrimary)

                Link(destination: URL(string: "mailto:support@example.com")!) {
                    HStack {
                        DSSettingRow(
                            icon: "envelope.fill",
                            iconColor: DS.Color.accent,
                            title: "Email Support",
                            value: nil
                        )
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .foregroundStyle(DS.Color.textPrimary)
            } header: { Text("Get Help") }

            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    DSSettingRow(
                        icon: "stethoscope",
                        iconColor: DS.Color.error,
                        title: "Diagnostics",
                        value: "Attach to report"
                    )
                }
            } header: { Text("Diagnostics") }
             footer: { Text("Include a copy of the diagnostics report when contacting support.") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Contact Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
