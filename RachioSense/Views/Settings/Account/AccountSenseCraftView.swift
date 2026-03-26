import SwiftUI

struct AccountSenseCraftView: View {
    @EnvironmentObject private var appState: AppState
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var accountEmail = ""
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: TestResult? = nil
    @State private var saveMessage: String? = nil
    @State private var showSignOutConfirmation = false
    @State private var deviceCount: Int? = nil

    struct TestResult {
        let success: Bool
        let message: String
    }

    var isConnected: Bool { appState.hasSenseCraftCredentials }

    var body: some View {
        List {
            // Status section
            Section {
                HStack(spacing: DS.Spacing.md) {
                    DSStatusDot(status: isConnected ? .online : .offline, size: 10)
                    Text(isConnected ? "Connected" : "Not Connected")
                        .font(DS.Font.cardTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                    if let count = deviceCount {
                        Text("\(count) sensors")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }

                if !accountEmail.isEmpty {
                    HStack {
                        Text("Account")
                            .foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text(accountEmail)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                }
            } header: { Text("Status") }

            // Credentials
            Section {
                HStack {
                    Text("API Key")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    SecureField("Required", text: $apiKey)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                HStack {
                    Text("API Secret")
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    SecureField("Required", text: $apiSecret)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("Credentials")
            } footer: {
                Text("Find these at sensecap.seeed.cc → Account → API Keys")
            }

            // Test result
            if let result = testResult {
                Section {
                    DSInlineBanner(
                        message: result.message,
                        style: result.success ? .success : .error
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                }
            }

            if let msg = saveMessage {
                Section {
                    DSInlineBanner(message: msg, style: .success)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }
            }

            // Actions
            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Spacer()
                        if isTesting {
                            ProgressView().scaleEffect(0.85)
                            Text("Testing…")
                        } else {
                            Label("Test Connection", systemImage: "network")
                        }
                        Spacer()
                    }
                }
                .disabled(apiKey.isEmpty || apiSecret.isEmpty || isTesting || isSaving)

                Button {
                    Task { await saveCredentials() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().scaleEffect(0.85)
                            Text("Saving…")
                        } else {
                            Label("Save Credentials", systemImage: "checkmark")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving || isTesting)
            }

            if isConnected {
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("SenseCraft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadCredentials() }
        .confirmationDialog("Sign out of SenseCraft?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove your SenseCraft API credentials from the Keychain.")
        }
    }

    private func loadCredentials() {
        apiKey = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) ?? ""
        apiSecret = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPISecret) ?? ""
    }

    private func saveCredentials() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if !apiKey.isEmpty {
                try KeychainService.shared.save(apiKey, forKey: KeychainKey.senseCraftAPIKey)
            }
            if !apiSecret.isEmpty {
                try KeychainService.shared.save(apiSecret, forKey: KeychainKey.senseCraftAPISecret)
            }
            appState.refreshCredentialStatus()
            saveMessage = "Credentials saved successfully."
            HapticFeedback.notification(.success)
        } catch {
            saveMessage = "Failed to save: \(error.localizedDescription)"
            HapticFeedback.notification(.error)
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        _ = try? KeychainService.shared.save(apiKey, forKey: KeychainKey.senseCraftAPIKey)
        _ = try? KeychainService.shared.save(apiSecret, forKey: KeychainKey.senseCraftAPISecret)

        do {
            let devices = try await SenseCraftAPI.shared.listDevices()
            deviceCount = devices.count
            testResult = TestResult(success: true, message: "Connected! Found \(devices.count) device(s).")
            HapticFeedback.notification(.success)
        } catch {
            testResult = TestResult(success: false, message: friendlyError(error))
            HapticFeedback.notification(.error)
        }
    }

    private func signOut() {
        _ = try? KeychainService.shared.delete(forKey: KeychainKey.senseCraftAPIKey)
        _ = try? KeychainService.shared.delete(forKey: KeychainKey.senseCraftAPISecret)
        appState.refreshCredentialStatus()
        apiKey = ""
        apiSecret = ""
        deviceCount = nil
        testResult = nil
    }

    private func friendlyError(_ error: Error) -> String {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("401") || desc.contains("unauthorized") { return "Invalid credentials — check your API Key and Secret" }
        if desc.contains("network") || error is URLError { return "Network error — check your connection" }
        return error.localizedDescription
    }
}
