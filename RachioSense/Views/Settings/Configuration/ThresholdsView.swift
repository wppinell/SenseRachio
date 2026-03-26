import SwiftUI

struct ThresholdsView: View {
    @AppStorage(AppStorageKey.dryThreshold) private var dryThreshold: Double = 25
    @AppStorage(AppStorageKey.lowThreshold) private var lowThreshold: Double = 40
    @AppStorage(AppStorageKey.autoWaterThreshold) private var autoWaterThreshold: Double = 20

    @State private var showResetConfirmation = false

    var body: some View {
        List {
            Section {
                DSInlineBanner(
                    message: "These are global defaults. Individual sensor thresholds can be set in Sensor-Zone Links.",
                    style: .info
                )
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }

            Section {
                thresholdSlider(
                    label: "High Level",
                    description: "Soil moisture is at a good high level",
                    value: $lowThreshold,
                    range: 30...80
                )
            } header: { Text("High Level") }
             footer: { Text("Alert when moisture drops to or below this level. Current: \(Int(lowThreshold))%") }

            Section {
                thresholdSlider(
                    label: "Dry Level",
                    description: "Soil moisture is critically dry",
                    value: $dryThreshold,
                    range: 10...50
                )
            } header: { Text("Dry Level") }
             footer: { Text("Alert when moisture drops to or below this level. Current: \(Int(dryThreshold))%") }

            Section {
                thresholdSlider(
                    label: "Auto-water Trigger",
                    description: "Automatically start linked zone",
                    value: $autoWaterThreshold,
                    range: 5...40
                )
            } header: { Text("Auto-water Trigger") }
             footer: { Text("If auto-water is enabled for a sensor, irrigation will start when moisture drops to \(Int(autoWaterThreshold))%.") }

            // Live preview
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("Preview")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.textSecondary)

                    ForEach([10.0, autoWaterThreshold, dryThreshold, lowThreshold, 55.0, 80.0], id: \.self) { val in
                        HStack(spacing: DS.Spacing.sm) {
                            DSMoistureBar(value: val)
                            Text("\(Int(val))%")
                                .font(DS.Font.label)
                                .foregroundStyle(DS.Color.moisture(val))
                                .frame(width: 40, alignment: .trailing)
                            Text(levelLabel(val))
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
                .padding(.vertical, DS.Spacing.sm)
            } header: { Text("Visual Preview") }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Thresholds")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset thresholds?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) { resetDefaults() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func thresholdSlider(label: String, description: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(DS.Font.cardBody)
                    Text(description).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Color.moisture(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            Slider(value: value, in: range, step: 1)
                .tint(DS.Color.moisture(value.wrappedValue))
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func levelLabel(_ val: Double) -> String {
        if val <= autoWaterThreshold { return "🔴 Auto-water" }
        if val <= dryThreshold       { return "🟡 Dry" }
        if val <= lowThreshold       { return "🟢 Good" }
        return "🔵 Above high"
    }

    private func resetDefaults() {
        dryThreshold = 25
        lowThreshold = 40
        autoWaterThreshold = 20
        HapticFeedback.notification(.success)
    }
}
