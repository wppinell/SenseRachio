import SwiftUI

struct WeatherIntegrationView: View {
    @AppStorage(AppStorageKey.weatherSource) private var weatherSource = "rachio"
    @AppStorage(AppStorageKey.rainSkipEnabled) private var rainSkip = true
    @AppStorage(AppStorageKey.rainSkipThreshold) private var rainThreshold = 6.0
    @AppStorage(AppStorageKey.freezeSkipEnabled) private var freezeSkip = true
    @AppStorage(AppStorageKey.freezeSkipThreshold) private var freezeThreshold = 2.0
    @AppStorage(AppStorageKey.windSkipEnabled) private var windSkip = false
    @AppStorage(AppStorageKey.windSkipThreshold) private var windThreshold = 30.0
    @AppStorage(AppStorageKey.saturationSkipEnabled) private var saturationSkip = false
    @AppStorage(AppStorageKey.saturationSkipThreshold) private var saturationThreshold = 70.0
    @AppStorage(AppStorageKey.forecastLookahead) private var lookahead = 48

    var body: some View {
        List {
            Section {
                Picker("Weather Source", selection: $weatherSource) {
                    Text("Rachio (built-in)").tag("rachio")
                    Text("National Weather Service").tag("national")
                    Text("Open-Meteo (free)").tag("openmeteo")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("Weather Source") }
             footer: { weatherSourceFooter }

            Section {
                skipRow(
                    title: "Rain Skip",
                    detail: "Skip watering if rain is forecast",
                    enabled: $rainSkip,
                    threshold: $rainThreshold,
                    range: 1.0...25.0,
                    unit: "mm",
                    format: "%.0f mm expected rain"
                )

                skipRow(
                    title: "Freeze Skip",
                    detail: "Skip watering if temperature is near freezing",
                    enabled: $freezeSkip,
                    threshold: $freezeThreshold,
                    range: -5.0...10.0,
                    unit: "°C",
                    format: "Below %.0f°C"
                )

                skipRow(
                    title: "Wind Skip",
                    detail: "Skip watering in high wind conditions",
                    enabled: $windSkip,
                    threshold: $windThreshold,
                    range: 10.0...80.0,
                    unit: "km/h",
                    format: "Above %.0f km/h"
                )

                skipRow(
                    title: "Saturation Skip",
                    detail: "Skip if soil is already saturated",
                    enabled: $saturationSkip,
                    threshold: $saturationThreshold,
                    range: 50.0...100.0,
                    unit: "%",
                    format: "Above %.0f%% saturation"
                )
            } header: { Text("Smart Skips") }
             footer: { Text("Irrigation will be skipped automatically when weather conditions exceed these thresholds.") }

            Section {
                Picker("Forecast Lookahead", selection: $lookahead) {
                    Text("24 hours").tag(24)
                    Text("48 hours").tag(48)
                    Text("72 hours").tag(72)
                }
            } header: { Text("Forecast Window") }
             footer: { Text("How far ahead to look when deciding whether to skip irrigation.") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Weather Integration")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var weatherSourceFooter: some View {
        switch weatherSource {
        case "rachio":  Text("Uses Rachio's built-in weather data. Requires Rachio connection.")
        case "national": Text("Uses the National Weather Service API. US only, no account required.")
        default:         Text("Uses Open-Meteo global weather data. Free, no account required.")
        }
    }

    @ViewBuilder
    private func skipRow(
        title: String,
        detail: String,
        enabled: Binding<Bool>,
        threshold: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.Font.cardBody)
                    Text(detail).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Toggle("", isOn: enabled)
                    .tint(DS.Color.accent)
                    .labelsHidden()
            }

            if enabled.wrappedValue {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack {
                        Text("Threshold")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text(String(format: "%.0f \(unit)", threshold.wrappedValue))
                            .font(DS.Font.label)
                            .foregroundStyle(DS.Color.accent)
                            .monospacedDigit()
                    }
                    Slider(value: threshold, in: range, step: 1)
                        .tint(DS.Color.accent)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .animation(.easeInOut(duration: 0.2), value: enabled.wrappedValue)
    }
}
