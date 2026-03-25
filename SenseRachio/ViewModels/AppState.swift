import Foundation
import Combine

// MARK: - AppState

final class AppState: ObservableObject {
    @Published private(set) var hasSenseCraftCredentials: Bool = false
    @Published private(set) var hasRachioCredentials: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showErrorBanner: Bool = false
    @Published var selectedTab: Int = 0

    var hasAnyCredentials: Bool {
        hasSenseCraftCredentials || hasRachioCredentials
    }

    init() {
        refreshCredentialStatus()
    }

    // MARK: - Refresh

    func refreshCredentialStatus() {
        let scKey = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey)
        let scSecret = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPISecret)
        hasSenseCraftCredentials = !(scKey ?? "").isEmpty && !(scSecret ?? "").isEmpty

        let rachioKey = KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey)
        hasRachioCredentials = !(rachioKey ?? "").isEmpty
    }

    // MARK: - Clear All

    func clearAll() {
        KeychainService.shared.deleteAll()
        refreshCredentialStatus()
    }

    // MARK: - Error Banner

    func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = message
            self?.showErrorBanner = true
        }
    }

    func dismissError() {
        errorMessage = nil
        showErrorBanner = false
    }
}
