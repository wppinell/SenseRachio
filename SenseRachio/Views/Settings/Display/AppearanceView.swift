import SwiftUI

struct AppearanceView: View {
    @AppStorage(AppStorageKey.theme) private var theme = "system"
    @AppStorage(AppStorageKey.accentColor) private var accentColorName = "Blue"
    @AppStorage(AppStorageKey.animationsEnabled) private var animations = true
    @AppStorage(AppStorageKey.hapticsEnabled) private var haptics = true
    @AppStorage(AppStorageKey.iconStyle) private var iconStyle = "filled"
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
    }
}
