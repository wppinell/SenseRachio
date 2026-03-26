import Foundation

// MARK: - SenseCraft Domain Models

struct SenseCraftDevice: Codable {
    let deviceEui: String
    let deviceName: String
    let expiryDate: Date?
    let daysUntilExpiry: Int?
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
                    deviceName: item.deviceName ?? item.deviceEui,
                    expiryDate: item.expiryDate,
                    daysUntilExpiry: item.daysUntilExpiry
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
    
    // MARK: - Fetch Historical Data (up to 7 days)
    
    struct HistoricalReading {
        let timestamp: Date
        let moisture: Double?
        let tempC: Double?
    }
    
    /// Returns raw JSON string from history endpoint — for diagnostics only.
    func fetchHistoryRaw(eui: String, hours: Int = 24) async throws -> String {
        let endTime = Int(Date().timeIntervalSince1970 * 1000)
        let startTime = endTime - (hours * 3600 * 1000)
        let request = try makeAuthenticatedRequest(
            path: "/list_telemetry_data",
            queryItems: [
                URLQueryItem(name: "device_eui", value: eui),
                URLQueryItem(name: "time_start", value: String(startTime)),
                URLQueryItem(name: "time_end", value: String(endTime))
            ]
        )
        let (data, _) = try await session.data(for: request)
        
        // Pretty print if possible
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return String(data: data, encoding: .utf8) ?? "<unreadable>"
    }

    /// Fetches historical telemetry data for a sensor, paging in 24h chunks if needed.
    /// - Parameters:
    ///   - eui: Device EUI
    ///   - hours: Number of hours to fetch (default 168 = 7 days)
    /// - Returns: Array of historical readings sorted by time ascending
    func fetchHistory(eui: String, hours: Int = 168) async throws -> [HistoricalReading] {
        // If > 24h, fetch in 24h chunks to work around API result limits
        if hours > 24 {
            var allReadings: [HistoricalReading] = []
            let chunkHours = 24
            let chunks = Int(ceil(Double(hours) / Double(chunkHours)))
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)

            for i in 0..<chunks {
                let chunkEndMs   = nowMs - (i * chunkHours * 3600 * 1000)
                let chunkStartMs = chunkEndMs - (chunkHours * 3600 * 1000)
                let chunk = try await fetchHistoryChunk(eui: eui, startMs: chunkStartMs, endMs: chunkEndMs)
                print("[SenseCraft] \(eui.suffix(4)) chunk \(i+1)/\(chunks): \(chunk.count) readings")
                allReadings.append(contentsOf: chunk)
            }

            return allReadings.sorted { $0.timestamp < $1.timestamp }
        }

        // Single chunk for <= 24h
        let endTime = Int(Date().timeIntervalSince1970 * 1000)
        let startTime = endTime - (hours * 3600 * 1000)
        return try await fetchHistoryChunk(eui: eui, startMs: startTime, endMs: endTime)
    }

    func fetchHistoryChunk(eui: String, startMs: Int, endMs: Int) async throws -> [HistoricalReading] {
        let request = try makeAuthenticatedRequest(
            path: "/list_telemetry_data",
            queryItems: [
                URLQueryItem(name: "device_eui", value: eui),
                URLQueryItem(name: "time_start", value: String(startMs)),
                URLQueryItem(name: "time_end", value: String(endMs))
            ]
        )
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SenseCraftAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw SenseCraftAPIError.httpError(httpResponse.statusCode)
        }
        
        // Parse using JSONSerialization — response uses nested arrays, not objects
        // Structure: { "code": "0", "data": { "list": [channelDescriptors, dataSeries] } }
        // channelDescriptors: [[channelIdx, measurementId], ...]
        // dataSeries: [[[value, isoTimestamp], ...], ...]  — one series per channel
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String, code == "0",
              let dataObj = json["data"] as? [String: Any],
              let list = dataObj["list"] as? [Any],
              list.count >= 2,
              let channelDescriptors = list[0] as? [[Any]],
              let dataSeriesRaw = list[1] as? [Any] else {
            throw SenseCraftAPIError.invalidResponse
        }
        
        // Map measurementId → series index
        var measurementIdToIndex: [String: Int] = [:]
        for (i, descriptor) in channelDescriptors.enumerated() {
            if let measurementId = descriptor.count > 1 ? descriptor[1] as? String : nil {
                measurementIdToIndex[measurementId] = i
            }
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Helper to extract [[value, timestamp]] series at index
        func series(at index: Int?) -> [[Any]] {
            guard let i = index, i < dataSeriesRaw.count,
                  let s = dataSeriesRaw[i] as? [[Any]] else { return [] }
            return s
        }
        
        let moistureSeries = series(at: measurementIdToIndex[moistureMeasurementID])
        let tempSeries     = series(at: measurementIdToIndex[tempMeasurementID])
        
        // Build temp lookup keyed by ISO timestamp string
        var tempByTimestamp: [String: Double] = [:]
        for point in tempSeries {
            if point.count >= 2,
               let value = point[0] as? Double,
               let ts = point[1] as? String {
                tempByTimestamp[ts] = value
            }
        }
        
        // Build readings from moisture series
        var readings: [HistoricalReading] = []
        for point in moistureSeries {
            guard point.count >= 2,
                  let moisture = point[0] as? Double,
                  let tsString = point[1] as? String,
                  let date = isoFormatter.date(from: tsString) else { continue }
            
            readings.append(HistoricalReading(
                timestamp: date,
                moisture: moisture,
                tempC: tempByTimestamp[tsString]
            ))
        }
        
        return readings.sorted { $0.timestamp < $1.timestamp }
    }
}
