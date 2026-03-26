import SwiftUI

struct AppearanceView: View {
    @AppStorage(AppStorageKey.theme) private var theme = "system"
    @AppStorage(AppStorageKey.accentColor) private var accentColorName = "Blue"
    @AppStorage(AppStorageKey.animationsEnabled) private var animations = true
    @AppStorage(AppStorageKey.hapticsEnabled) private var haptics = true
    @AppStorage(AppStorageKey.iconStyle) private var iconStyle = "filled"
    @AppStorage(AppStorageKey.graphYMin) private var graphYMin = 15.0
    @AppStorage(AppStorageKey.graphYMax) private var graphYMax = 45.0
    @AppStorage(AppStorageKey.trendChartPeriod) private var defaultChartPeriod = "3d"
    @Environment(\.colorScheme) private var colorScheme

    private let accentColors: [(name: String, color: Color)] = [
        ("Blue",   Color(hex: "0066FF")),
        ("Green",  Color(hex: "22C55E")),
        ("Purple", Color(hex: "8B5CF6")),
        ("Orange", Color(hex: "F97316")),
        ("Leaf",   Color(hex: "16A34A")),
    ]

    var body: some View {
        List {
            // Theme
            Section {
                Picker("Theme", selection: $theme) {
                    Label("Light", systemImage: "sun.max.fill").tag("light")
                    Label("Dark", systemImage: "moon.fill").tag("dark")
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("Theme") }

            // Accent Color
            Section {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: DS.Spacing.md) {
                    ForEach(accentColors, id: \.name) { item in
                        Button {
                            accentColorName = item.name
                            if haptics { HapticFeedback.impact(.light) }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 44, height: 44)
                                if accentColorName == item.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, DS.Spacing.sm)

                HStack {
                    Text("Selected")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    Text(accentColorName)
                        .foregroundStyle(DS.Color.accentOptions[accentColorName] ?? DS.Color.accent)
                        .fontWeight(.semibold)
                }
            } header: { Text("Accent Color") }

            // Interactions
            Section {
                Toggle("Animations", isOn: $animations)
                    .tint(DS.Color.accent)
                Toggle("Haptic Feedback", isOn: $haptics)
                    .tint(DS.Color.accent)
            } header: { Text("Interactions") }

            // Icon Style
            Section {
                Picker("Icon Style", selection: $iconStyle) {
                    HStack {
                        Image(systemName: "sensor.fill")
                        Text("Filled")
                    }.tag("filled")
                    HStack {
                        Image(systemName: "sensor")
                        Text("Outlined")
                    }.tag("outlined")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: { Text("Icon Style") }

            // Graph Default Period
            Section {
                Picker("Default Period", selection: $defaultChartPeriod) {
                    Text("1 day").tag("1d")
                    Text("2 days").tag("2d")
                    Text("3 days").tag("3d")
                    Text("4 days").tag("4d")
                    Text("5 days").tag("5d")
                    Text("1 week").tag("1w")
                    Text("2 weeks").tag("2w")
                }
            } header: { Text("Graph Default Period") }
              footer: { Text("The time range shown when you first open the Graphs tab. Default: 3 days.") }

            // Graph Scale
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack {
                        Text("Y-Axis Min")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("\(Int(graphYMin))%")
                            .foregroundStyle(DS.Color.textPrimary)
                            .monospacedDigit()
                    }
                    Slider(value: $graphYMin, in: 0...50, step: 5)
                        .tint(DS.Color.accent)
                        .onChange(of: graphYMin) { _, newVal in
                            if newVal >= graphYMax { graphYMax = newVal + 5 }
                        }
                }
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack {
                        Text("Y-Axis Max")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("\(Int(graphYMax))%")
                            .foregroundStyle(DS.Color.textPrimary)
                            .monospacedDigit()
                    }
                    Slider(value: $graphYMax, in: 20...100, step: 5)
                        .tint(DS.Color.accent)
                        .onChange(of: graphYMax) { _, newVal in
                            if newVal <= graphYMin { graphYMin = newVal - 5 }
                        }
                }
            } header: { Text("Graph Scale") }
              footer: { Text("Sets the moisture % range displayed on all graphs. Default: 15%–45%.") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
    }
}
