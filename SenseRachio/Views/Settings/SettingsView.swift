import SwiftUI
import SwiftData

struct SettingsView: View {
    let isOnboarding: Bool

    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var senseCraftAPIKey: String = ""
    @State private var senseCraftAPISecret: String = ""
    @State private var rachioAPIKey: String = ""

    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    @State private var saveMessageIsError = false

    @State private var isTestingSenseCraft = false
    @State private var senseCraftTestResult: String? = nil
    @State private var senseCraftTestSuccess = false

    @State private var isTestingRachio = false
    @State private var rachioTestResult: String? = nil
    @State private var rachioTestSuccess = false

    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                if isOnboarding {
                    onboardingHeader
                }

                if let message = saveMessage {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: saveMessageIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(saveMessageIsError ? .red : .green)
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(saveMessageIsError ? .red : .green)
                        }
                    }
                    .listRowBackground(saveMessageIsError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
                }

                // MARK: SenseCraft Section
                Section {
                    SecureField("API Key", text: $senseCraftAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("API Secret", text: $senseCraftAPISecret)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if let result = senseCraftTestResult {
                        HStack(spacing: 8) {
                            Image(systemName: senseCraftTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(senseCraftTestSuccess ? .green : .red)
                            Text(result)
                                .font(.footnote)
                                .foregroundStyle(senseCraftTestSuccess ? .green : .red)
                        }
                    }

                    Button {
                        Task { await testSenseCraftConnection() }
                    } label: {
                        if isTestingSenseCraft {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Testing...")
                            }
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(senseCraftAPIKey.isEmpty || senseCraftAPISecret.isEmpty || isTestingSenseCraft)
                } header: {
                    Label("SenseCraft (Seeed)", systemImage: "sensor.fill")
                } footer: {
                    Text("Your SenseCraft API Key and Secret from sensecap.seeed.cc.")
                }

                // MARK: Rachio Section
                Section {
                    SecureField("API Key", text: $rachioAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if let result = rachioTestResult {
                        HStack(spacing: 8) {
                            Image(systemName: rachioTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(rachioTestSuccess ? .green : .red)
                            Text(result)
                                .font(.footnote)
                                .foregroundStyle(rachioTestSuccess ? .green : .red)
                        }
                    }

                    Button {
                        Task { await testRachioConnection() }
                    } label: {
                        if isTestingRachio {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Testing...")
                            }
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(rachioAPIKey.isEmpty || isTestingRachio)
                } header: {
                    Label("Rachio", systemImage: "drop.fill")
                } footer: {
                    Text("Your Rachio API key from app.rach.io/account/.")
                }

                // MARK: Save Button
                Section {
                    Button {
                        Task { await saveCredentials() }
                    } label: {
                        if isSaving {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Saving...")
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text("Save Credentials")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }

                // MARK: Sensor-Zone Linking
                if !isOnboarding && appState.hasAnyCredentials {
                    Section {
                        SensorZoneLinkView()
                    } header: {
                        Label("Sensor-Zone Links", systemImage: "link")
                    } footer: {
                        Text("Link each sensor to an irrigation zone and set a moisture threshold for automatic alerts.")
                    }
                }

                // MARK: Clear Credentials
                if !isOnboarding && appState.hasAnyCredentials {
                    Section {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Text("Clear All Credentials")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                // MARK: App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle(isOnboarding ? "Welcome to SenseRachio" : "Settings")
            .navigationBarTitleDisplayMode(isOnboarding ? .large : .inline)
            .confirmationDialog(
                "Clear all credentials?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    appState.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all stored API keys from the Keychain.")
            }
        }
        .onAppear {
            loadExistingCredentials()
        }
    }

    // MARK: - Onboarding Header

    private var onboardingHeader: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)
                Text("Connect your SenseCraft soil sensors and Rachio irrigation system to monitor and control your garden from one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Load Existing Credentials

    private func loadExistingCredentials() {
        senseCraftAPIKey = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) ?? ""
        senseCraftAPISecret = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPISecret) ?? ""
        rachioAPIKey = KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) ?? ""
    }

    // MARK: - Save

    private func saveCredentials() async {
        isSaving = true
        saveMessage = nil

        do {
            if !senseCraftAPIKey.isEmpty {
                try KeychainService.shared.save(senseCraftAPIKey, forKey: KeychainKey.senseCraftAPIKey)
            }
            if !senseCraftAPISecret.isEmpty {
                try KeychainService.shared.save(senseCraftAPISecret, forKey: KeychainKey.senseCraftAPISecret)
            }
            if !rachioAPIKey.isEmpty {
                try KeychainService.shared.save(rachioAPIKey, forKey: KeychainKey.rachioAPIKey)
            }

            appState.refreshCredentialStatus()
            saveMessage = "Credentials saved successfully."
            saveMessageIsError = false
        } catch {
            saveMessage = "Failed to save: \(error.localizedDescription)"
            saveMessageIsError = true
        }
        isSaving = false
    }

    // MARK: - Test SenseCraft

    private func testSenseCraftConnection() async {
        isTestingSenseCraft = true
        senseCraftTestResult = nil

        // Temporarily write to keychain for the test
        try? KeychainService.shared.save(senseCraftAPIKey, forKey: KeychainKey.senseCraftAPIKey)
        try? KeychainService.shared.save(senseCraftAPISecret, forKey: KeychainKey.senseCraftAPISecret)

        do {
            let devices = try await SenseCraftAPI.shared.listDevices()
            senseCraftTestResult = "Connected! Found \(devices.count) device(s)."
            senseCraftTestSuccess = true
        } catch {
            senseCraftTestResult = friendlyErrorMessage(for: error)
            senseCraftTestSuccess = false
        }
        isTestingSenseCraft = false
    }

    // MARK: - Test Rachio

    private func testRachioConnection() async {
        isTestingRachio = true
        rachioTestResult = nil

        try? KeychainService.shared.save(rachioAPIKey, forKey: KeychainKey.rachioAPIKey)

        do {
            let devices = try await RachioAPI.shared.getDevices()
            rachioTestResult = "Connected! Found \(devices.count) device(s)."
            rachioTestSuccess = true
        } catch {
            rachioTestResult = friendlyErrorMessage(for: error)
            rachioTestSuccess = false
        }
        isTestingRachio = false
    }

    // MARK: - Error Helpers

    private func friendlyErrorMessage(for error: Error) -> String {
        let description = error.localizedDescription.lowercased()
        if description.contains("missingcredentials") || description.contains("credentials not found") {
            return "No API key entered"
        }
        if let urlError = error as? URLError {
            _ = urlError
            return "Network error — check your connection"
        }
        if description.contains("http 401") || description.contains("returned http 401") {
            return "Invalid API key — check your credentials"
        }
        if description.contains("http 404") || description.contains("returned http 404") {
            return "Service not found — please report this bug"
        }
        // Check RachioAPIError / SenseCraftAPIError http codes via pattern
        if description.contains("401") {
            return "Invalid API key — check your credentials"
        }
        if description.contains("404") {
            return "Service not found — please report this bug"
        }
        return error.localizedDescription
    }
}

#Preview {
    SettingsView(isOnboarding: true)
        .environmentObject(AppState())
}
