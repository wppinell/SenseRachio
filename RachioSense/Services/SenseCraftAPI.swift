import Foundation

// MARK: - SenseCraft Domain Models

struct SenseCraftDevice: Codable {
    let deviceEui: String
    let deviceName: String
}

struct SenseCraftReading: Codable {
    let moisture: Double?
    let tempC: Double?
}

// MARK: - SenseCraft API Errors

enum SenseCraftAPIError: Error, LocalizedError {
    case missingCredentials
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "SenseCraft credentials not found. Please configure them in Settings."
        case .invalidResponse:
            return "Invalid response from SenseCraft API."
        case .httpError(let code):
            return "SenseCraft API returned HTTP \(code)."
        case .decodingError(let error):
            return "Failed to decode SenseCraft response: \(error.localizedDescription)"
        case .apiError(let msg):
            return "SenseCraft API error: \(msg)"
        }
    }
}

// MARK: - SenseCraftAPI

final class SenseCraftAPI {
    static let shared = SenseCraftAPI()

    private let baseURL = "https://sensecap.seeed.cc/openapi"
    private let session: URLSession

    // Measurement IDs
    private let moistureMeasurementID = "4103"
    private let tempMeasurementID = "4102"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Auth

    private func makeAuthenticatedRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard let apiKey = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey),
              let apiSecret = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPISecret),
              !apiKey.isEmpty, !apiSecret.isEmpty else {
            throw SenseCraftAPIError.missingCredentials
        }

        var components = URLComponents(string: baseURL + path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw SenseCraftAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // HTTP Basic Auth
        let credentials = "\(apiKey):\(apiSecret)"
        if let data = credentials.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return request
    }

    // MARK: - List Devices

    func listDevices() async throws -> [SenseCraftDevice] {
        let request = try makeAuthenticatedRequest(path: "/list_devices")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SenseCraftAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw SenseCraftAPIError.httpError(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(SenseCraftListDevicesResponse.self, from: data)
            if let msg = decoded.msg, decoded.code != "0" {
                throw SenseCraftAPIError.apiError(msg)
            }
            let items = decoded.data ?? []
            return items.map { item in
                SenseCraftDevice(
                    deviceEui: item.deviceEui,
                    deviceName: item.deviceName ?? item.deviceEui
                )
            }
        } catch let error as SenseCraftAPIError {
            throw error
        } catch {
            throw SenseCraftAPIError.decodingError(error)
        }
    }

    // MARK: - Fetch Latest Reading

    func fetchReading(eui: String) async throws -> SenseCraftReading {
        let request = try makeAuthenticatedRequest(
            path: "/view_latest_telemetry_data",
            queryItems: [URLQueryItem(name: "device_eui", value: eui)]
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SenseCraftAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw SenseCraftAPIError.httpError(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(SenseCraftTelemetryResponse.self, from: data)
            if let msg = decoded.msg, decoded.code != "0" {
                throw SenseCraftAPIError.apiError(msg)
            }

            // data is array of channels, each with a points array
            let allPoints = (decoded.data ?? []).flatMap { $0.points ?? [] }
            var moisture: Double? = nil
            var tempC: Double? = nil

            for point in allPoints {
                if point.measurementId == moistureMeasurementID {
                    moisture = point.measurementValue
                } else if point.measurementId == tempMeasurementID {
                    tempC = point.measurementValue
                }
            }

            return SenseCraftReading(moisture: moisture, tempC: tempC)
        } catch let error as SenseCraftAPIError {
            throw error
        } catch {
            throw SenseCraftAPIError.decodingError(error)
        }
    }
}
