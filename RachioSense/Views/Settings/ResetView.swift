import SwiftUI
import SwiftData

struct ResetView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var activeConfirmation: ConfirmationAction? = nil
    @State private var completedAction: String? = nil

    enum ConfirmationAction: Identifiable {
        case scClearCache, scClearCreds, scFull
        case rachioClearCache, rachioClearCreds, rachioFull
        case appClearCache, appClearLinks, appResetSettings
        case allReset

        var id: Self { self }
        var title: String {
            switch self {
            case .scClearCache:        return "Clear SenseCraft sensor cache?"
            case .scClearCreds:        return "Clear SenseCraft credentials?"
            case .scFull:              return "Full SenseCraft reset?"
            case .rachioClearCache:    return "Clear Rachio zone cache?"
            case .rachioClearCreds:    return "Clear Rachio credentials?"
            case .rachioFull:          return "Full Rachio reset?"
            case .appClearCache:       return "Clear all cache?"
            case .appClearLinks:       return "Clear all sensor-zone links?"
            case .appResetSettings:    return "Reset settings to defaults?"
            case .allReset:            return "Reset everything?"
            }
        }
        var message: String {
            switch self {
            case .scClearCache:     return "Removes cached SenseCraft sensor configurations from the local database."
            case .scClearCreds:     return "Removes SenseCraft API credentials from the Keychain."
            case .scFull:           return "Removes SenseCraft credentials, sensor configurations, and all cached readings."
            case .rachioClearCache: return "Removes cached Rachio zone configurations from the local database."
            case .rachioClearCreds: return "Removes Rachio API key from the Keychain."
            case .rachioFull:       return "Removes Rachio credentials, zone configurations, and device cache."
            case .appClearCache:    return "Removes all cached sensor and zone data."
            case .appClearLinks:    return "Removes all sensor-to-zone links and automation settings."
            case .appResetSettings: return "Resets all display, notification, and configuration settings to their default values."
            case .allReset:         return "This will remove ALL credentials, data, and settings. The app will return to its initial state. This cannot be undone."
            }
        }
        var buttonLabel: String {
            switch self {
            case .allReset:  return "Reset Everything"
            case .scFull, .rachioFull: return "Full Reset"
            default: return "Reset"
            }
        }
    }

    var body: some View {
        List {
            if let msg = completedAction {
                Section {
                    DSInlineBanner(message: msg, style: .success)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }
            }

            // MARK: SenseCraft
            Section {
                resetButton("Clear Sensor Cache", action: .scClearCache)
                resetButton("Clear Credentials", action: .scClearCreds)
                resetButton("Full Reset", subtitle: "Cache + credentials + sensor configs", action: .scFull)
            } header: { Text("SenseCraft") }

            // MARK: Rachio
            Section {
                resetButton("Clear Zone Cache", action: .rachioClearCache)
                resetButton("Clear Credentials", action: .rachioClearCreds)
                resetButton("Full Reset", subtitle: "Cache + credentials + zone configs", action: .rachioFull)
            } header: { Text("Rachio") }

            // MARK: App Data
            Section {
                resetButton("Clear All Cache", action: .appClearCache)
                resetButton("Clear Sensor-Zone Links", action: .appClearLinks)
                resetButton("Reset Settings to Defaults", action: .appResetSettings)
            } header: { Text("App Data") }

            // MARK: Nuclear
            Section {
                Button(role: .destructive) {
                    activeConfirmation = .allReset
                } label: {
                    HStack {
                        Spacer()
                        Label("Reset Everything", systemImage: "exclamationmark.triangle.fill")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .listRowBackground(DS.Color.errorMuted)
            } header: { Text("Complete Reset") }
             footer: { Text("Resets both services and all app data to factory defaults.") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reset")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            activeConfirmation?.title ?? "",
            isPresented: Binding(
                get: { activeConfirmation != nil },
                set: { if !$0 { activeConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = activeConfirmation {
                Button(action.buttonLabel, role: .destructive) {
                    performAction(action)
                    activeConfirmation = nil
                }
                Button("Cancel", role: .cancel) { activeConfirmation = nil }
            }
        } message: {
            Text(activeConfirmation?.message ?? "")
        }
    }

    @ViewBuilder
    private func resetButton(_ title: String, subtitle: String? = nil, action: ConfirmationAction) -> some View {
        Button(role: .destructive) {
            activeConfirmation = action
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
    }

    private func performAction(_ action: ConfirmationAction) {
        switch action {
        case .scClearCache:
            _ = try? modelContext.delete(model: SensorConfig.self)
            _ = try? modelContext.delete(model: SensorReading.self)
            _ = try? modelContext.save()
            completedAction = "SenseCraft sensor cache cleared."

        case .scClearCreds:
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.senseCraftAPIKey)
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.senseCraftAPISecret)
            appState.refreshCredentialStatus()
            completedAction = "SenseCraft credentials removed."

        case .scFull:
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.senseCraftAPIKey)
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.senseCraftAPISecret)
            _ = try? modelContext.delete(model: SensorConfig.self)
            _ = try? modelContext.delete(model: SensorReading.self)
            _ = try? modelContext.save()
            appState.refreshCredentialStatus()
            completedAction = "SenseCraft full reset complete."

        case .rachioClearCache:
            _ = try? modelContext.delete(model: ZoneConfig.self)
            _ = try? modelContext.save()
            completedAction = "Rachio zone cache cleared."

        case .rachioClearCreds:
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.rachioAPIKey)
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.rachioDeviceIds)
            appState.refreshCredentialStatus()
            completedAction = "Rachio credentials removed."

        case .rachioFull:
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.rachioAPIKey)
            _ = try? KeychainService.shared.delete(forKey: KeychainKey.rachioDeviceIds)
            _ = try? modelContext.delete(model: ZoneConfig.self)
            _ = try? modelContext.save()
            appState.refreshCredentialStatus()
            completedAction = "Rachio full reset complete."

        case .appClearCache:
            _ = try? modelContext.delete(model: SensorConfig.self)
            _ = try? modelContext.delete(model: ZoneConfig.self)
            _ = try? modelContext.delete(model: SensorReading.self)
            _ = try? modelContext.save()
            completedAction = "All cache cleared."

        case .appClearLinks:
            let descriptor = FetchDescriptor<SensorConfig>()
            let configs = (try? modelContext.fetch(descriptor)) ?? []
            for c in configs {
                c.linkedZoneId = nil
                c.autoWaterEnabled = false
            }
            _ = try? modelContext.save()
            completedAction = "All sensor-zone links removed."

        case .appResetSettings:
            resetAppStorageDefaults()
            completedAction = "Settings reset to defaults."

        case .allReset:
            appState.clearAll()
            _ = try? modelContext.delete(model: SensorConfig.self)
            _ = try? modelContext.delete(model: ZoneConfig.self)
            _ = try? modelContext.delete(model: SensorReading.self)
            _ = try? modelContext.delete(model: ZoneGroup.self)
            _ = try? modelContext.delete(model: DashboardCardOrder.self)
            _ = try? modelContext.save()
            resetAppStorageDefaults()
            completedAction = "Complete reset done. The app has been restored to its initial state."
        }
        HapticFeedback.notification(.success)
    }

    private func resetAppStorageDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? ""
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
