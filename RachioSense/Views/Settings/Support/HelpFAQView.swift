import SwiftUI

struct HelpFAQView: View {
    private let faqs: [(question: String, answer: String)] = [
        (
            "How do I get my SenseCraft API key?",
            "Log in to sensecap.seeed.cc → Click your profile → API Keys → Create a new access token. Copy both the Access ID (API Key) and Access Secret."
        ),
        (
            "How do I get my Rachio API key?",
            "Log in to app.rach.io → Menu → Account → API Access. Your API token will be displayed there."
        ),
        (
            "Why are my sensor readings not updating?",
            "Check that your sensors are online in the SenseCraft portal. The app refreshes data based on your configured Refresh Rate. Pull down to force a refresh."
        ),
        (
            "How do Sensor-Zone Links work?",
            "Link a soil sensor to an irrigation zone so you get alerts when moisture is low. If Auto-water is enabled, the linked zone will start automatically when moisture drops below the threshold."
        ),
        (
            "What are thresholds?",
            "Thresholds define moisture levels that trigger alerts. 'Low' is a warning level, 'Dry' is critical. You can set global defaults in Thresholds, or per-sensor overrides in Sensor-Zone Links."
        ),
        (
            "Why isn't background refresh working?",
            "Background App Refresh must be enabled in iOS Settings → General → Background App Refresh. iOS may delay or skip background tasks to preserve battery."
        ),
        (
            "Is my data stored in the cloud?",
            "No. All data is stored locally on your device using SwiftData. Your API credentials are stored securely in the iOS Keychain. The app communicates directly with SenseCraft and Rachio APIs."
        ),
        (
            "How do I reset the app?",
            "Go to Settings → Reset. You can selectively clear credentials, cache, or perform a full reset."
        ),
    ]

    @State private var expandedIndex: Int? = nil

    var body: some View {
        List {
            ForEach(faqs.indices, id: \.self) { i in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedIndex == i },
                            set: { expandedIndex = $0 ? i : nil }
                        )
                    ) {
                        Text(faqs[i].answer)
                            .font(DS.Font.cardBody)
                            .foregroundStyle(DS.Color.textSecondary)
                            .padding(.vertical, DS.Spacing.xs)
                    } label: {
                        Text(faqs[i].question)
                            .font(DS.Font.cardTitle)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
