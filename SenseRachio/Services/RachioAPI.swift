import Foundation

// MARK: - Rachio Domain Models

struct RachioZone: Codable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool
    let zoneNumber: Int?
    let lastWateredDate: Int?      // epoch milliseconds
    let lastWateredDuration: Int?  // seconds
    let imageUrl: String?
}

struct RachioDevice: Codable, Identifiable {
    let id: String
    let name: String
    let status: String?
    let on: Bool?
    let zones: [RachioZone]
}

// MARK: - Rachio API Errors

enum RachioAPIError: Error, LocalizedError {
    case missingCredentials
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Rachio credentials not found. Please configure them in Settings."
        case .invalidResponse:
            return "Invalid response from Rachio API."
        case .httpError(let code):
            return "Rachio API returned HTTP \(code)."
        case .decodingError(let error):
            return "Failed to decode Rachio response: \(error.localizedDescription)"
        case .apiError(let msg):
            return "Rachio API error: \(msg)"
        }
    }
}

// MARK: - RachioAPI

final class RachioAPI {
    static let shared = RachioAPI()

    private let baseURL = "https://api.rach.io/1/public"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Auth

    private func bearerToken() throws -> String {
        guard let token = KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey),
              !token.isEmpty else {
            throw RachioAPIError.missingCredentials
        }
        return token
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let token = try bearerToken()
        guard let url = URL(string: baseURL + path) else {
            throw RachioAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.httpBody = body
        }
        return request
    }

    // MARK: - Get Person Info

    private func getPersonId() async throws -> String {
        let request = try makeRequest(path: "/person/info")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw RachioAPIError.httpError(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(RachioPersonInfoResponse.self, from: data)
            return decoded.id
        } catch {
            throw RachioAPIError.decodingError(error)
        }
    }

    // MARK: - Discover Device IDs via /person/{personId}

    private func fetchDeviceIds(personId: String) async throws -> [String] {
        let request = try makeRequest(path: "/person/\(personId)")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw RachioAPIError.httpError(httpResponse.statusCode)
        }

        let person = try JSONDecoder().decode(RachioPersonResponse.self, from: data)
        let ids = (person.devices ?? []).map(\.id)
        guard !ids.isEmpty else {
            throw RachioAPIError.apiError("No devices found in person response.")
        }
        return ids
    }

    // MARK: - Get Single Device

    private func fetchDevice(id: String) async throws -> RachioDevice {
        let request = try makeRequest(path: "/device/\(id)")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw RachioAPIError.httpError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(RachioDevice.self, from: data)
        } catch {
            throw RachioAPIError.decodingError(error)
        }
    }

    // MARK: - Get Devices

    func getDevices() async throws -> [RachioDevice] {
        let personId = try await getPersonId()
        print("[RachioAPI] personId: \(personId)")

        // Discover device IDs via /person/{personId}, fall back to cached Keychain value
        let deviceIds: [String]
        if let ids = try? await fetchDeviceIds(personId: personId), !ids.isEmpty {
            // Cache for future resilience
            try? KeychainService.shared.save(ids.joined(separator: ","), forKey: KeychainKey.rachioDeviceIds)
            deviceIds = ids
        } else if let cached = KeychainService.shared.load(forKey: KeychainKey.rachioDeviceIds),
                  !cached.isEmpty {
            deviceIds = cached.split(separator: ",").map(String.init)
        } else {
            throw RachioAPIError.apiError("Could not discover Rachio devices. Try saving your API key and testing the connection again.")
        }
        print("[RachioAPI] deviceIds: \(deviceIds)")

        var devices: [RachioDevice] = []
        for id in deviceIds {
            let device = try await fetchDevice(id: id)
            print("[RachioAPI] fetched device: \(device.name)")
            devices.append(device)
        }
        return devices
    }

    // MARK: - Start Zone

    func startZone(id: String, duration: Int) async throws {
        let body = RachioZoneStartRequest(id: id, duration: duration)
        let bodyData = try JSONEncoder().encode(body)
        let request = try makeRequest(path: "/zone/start", method: "PUT", body: bodyData)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }
        guard (200...204).contains(httpResponse.statusCode) else {
            throw RachioAPIError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Stop Zone

    func stopZone(id: String) async throws {
        let body = RachioZoneStopRequest(id: id)
        let bodyData = try JSONEncoder().encode(body)
        let request = try makeRequest(path: "/zone/stop", method: "PUT", body: bodyData)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }
        guard (200...204).contains(httpResponse.statusCode) else {
            throw RachioAPIError.httpError(httpResponse.statusCode)
        }
    }
}
