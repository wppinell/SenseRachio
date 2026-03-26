import SwiftUI

struct AccountRachioView: View {
    @EnvironmentObject private var appState: AppState
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: TestResult? = nil
    @State private var saveMessage: String? = nil
    @State private var showSignOutConfirmation = false
    @State private var deviceInfo: DeviceInfo? = nil

    struct TestResult {
        let success: Bool
        let message: String
    }

    struct DeviceInfo {
        let deviceCount: Int
        let zoneCount: Int
        let deviceNames: [String]
    }

    var isConnected: Bool { appState.hasRachioCredentials }

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
                    if let info = deviceInfo {
                        Text("\(info.zoneCount) zones")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }

                if let info = deviceInfo {
                    ForEach(info.deviceNames, id: \.self) { name in
                        HStack {
                            Text("Controller")
                                .foregroundStyle(DS.Color.textSecondary)
                            Spacer()
                            Text(name)
                                .foregroundStyle(DS.Color.textPrimary)
                        }
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
            } header: {
                Text("Credentials")
            } footer: {
                Text("Find your API key at app.rach.io → Account → API Access")
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
                .disabled(apiKey.isEmpty || isTesting || isSaving)

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

                Link(destination: URL(string: "rachio://")!) {
                    HStack {
                        Spacer()
                        Label("View in Rachio App", systemImage: "arrow.up.right.square")
                        Spacer()
                    }
                }
                .foregroundStyle(DS.Color.accent)
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
        .navigationTitle("Rachio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadCredentials() }
        .confirmationDialog("Sign out of Rachio?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove your Rachio API key from the Keychain.")
        }
    }

    private func loadCredentials() {
        apiKey = KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) ?? ""
    }

    private func saveCredentials() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if !apiKey.isEmpty {
                try KeychainService.shared.save(apiKey, forKey: KeychainKey.rachioAPIKey)
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

        _ = try? KeychainService.shared.save(apiKey, forKey: KeychainKey.rachioAPIKey)

        do {
            let devices = try await RachioAPI.shared.getDevices()
            let zoneCount = devices.flatMap(\.zones).filter(\.enabled).count
            deviceInfo = DeviceInfo(
                deviceCount: devices.count,
                zoneCount: zoneCount,
                deviceNames: devices.map(\.name)
            )
            testResult = TestResult(
                success: true,
                message: "Connected! Found \(devices.count) device(s) with \(zoneCount) enabled zone(s)."
            )
            HapticFeedback.notification(.success)
        } catch {
            testResult = TestResult(success: false, message: friendlyError(error))
            HapticFeedback.notification(.error)
        }
    }

    private func signOut() {
        _ = try? KeychainService.shared.delete(forKey: KeychainKey.rachioAPIKey)
        _ = try? KeychainService.shared.delete(forKey: KeychainKey.rachioDeviceIds)
        appState.refreshCredentialStatus()
        apiKey = ""
        deviceInfo = nil
        testResult = nil
    }

    private func friendlyError(_ error: Error) -> String {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("401") || desc.contains("unauthorized") { return "Invalid API key — check your credentials" }
        if desc.contains("network") || error is URLError { return "Network error — check your connection" }
        return error.localizedDescription
    }
}
