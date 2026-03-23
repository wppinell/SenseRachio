import Foundation

// MARK: - Rachio Domain Models

struct RachioZone: Codable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool
}

struct RachioDevice: Codable, Identifiable {
    let id: String
    let name: String
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

    // MARK: - Get Devices

    func getDevices() async throws -> [RachioDevice] {
        let personId = try await getPersonId()
        let request = try makeRequest(path: "/person/\(personId)/device")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw RachioAPIError.httpError(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            // The API returns an array of devices directly
            let devices = try decoder.decode([RachioDevice].self, from: data)
            return devices
        } catch {
            throw RachioAPIError.decodingError(error)
        }
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
