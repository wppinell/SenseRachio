import Foundation
import os

private let logger = Logger(subsystem: "com.rachiosense", category: "RachioAPI")

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
    let scheduleRules: [RachioScheduleRule]?
}

struct RachioScheduleRule: Codable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool
    let startHour: Int?
    let startMinute: Int?
    let nextRunDate: Int?           // epoch milliseconds — Rachio-computed next run (FLEX schedules)
    let startDate: Int?             // epoch ms — FLEX schedule next run date
    let startDay: Int?
    let startMonth: Int?
    let startYear: Int?
    let zones: [RachioScheduleZone]
    let summary: String?
    let daysOfWeek: [String]?       // Fixed schedules: ["MONDAY", "WEDNESDAY", ...]
    let scheduleJobTypes: [String]? // e.g. ["DAY_INTERVAL", "FIXED_DAYS", "FLEX"]
    let cycleAndSoakStatus: String?
    
    var startTimeFormatted: String {
        let h = startHour ?? 0
        let m = startMinute ?? 0
        let ampm = h < 12 ? "AM" : "PM"
        let h12 = h == 0 ? 12 : h > 12 ? h - 12 : h
        return String(format: "%d:%02d %@", h12, m, ampm)
    }
    
    /// Number of times this schedule runs per week (as a Double for fractional intervals)
    var runsPerWeekDouble: Double {
        guard let types = scheduleJobTypes, !types.isEmpty else { return 1 }
        
        // Count DAY_OF_WEEK_N entries (specific days: 0=Sun, 1=Mon, ... 6=Sat)
        let dayOfWeekCount = types.filter { $0.hasPrefix("DAY_OF_WEEK_") }.count
        if dayOfWeekCount > 0 { return Double(dayOfWeekCount) }
        
        // INTERVAL_N = runs every N days → 7/N runs per week
        for type_ in types {
            if type_.hasPrefix("INTERVAL_"),
               let n = Int(type_.dropFirst("INTERVAL_".count)), n > 0 {
                return 7.0 / Double(n)
            }
        }
        
        return 1
    }
}

struct RachioWateringEvent: Identifiable {
    let id: String
    let zoneId: String
    let zoneName: String
    let startDate: Date
    let duration: Int  // seconds
}

struct RachioScheduleZone: Codable {
    let id: String
    let duration: Int
    
    enum CodingKeys: String, CodingKey {
        case id = "zoneId"
        case duration
    }
}

// Helper: look up schedule rules for a given zone ID
extension RachioDevice {
    func schedules(forZoneId zoneId: String) -> [(rule: RachioScheduleRule, duration: Int)] {
        guard let rules = scheduleRules else { return [] }
        return rules.compactMap { rule in
            guard rule.enabled,
                  let sz = rule.zones.first(where: { $0.id == zoneId }) else { return nil }
            return (rule: rule, duration: sz.duration)
        }
    }

    /// Compute next run Date for a zone using the same logic as ZoneCardView
    func nextRunDate(forZone zone: RachioZone) -> Date? {
        let entries = schedules(forZoneId: zone.id)
        guard !entries.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current
        var candidates: [Date] = []

        for entry in entries {
            let rule = entry.rule
            let isFlex = rule.startHour == nil
            var hour = rule.startHour ?? 12
            var minute = rule.startMinute ?? 0

            if isFlex, let lastMs = zone.lastWateredDate {
                let lastRun = Date(timeIntervalSince1970: Double(lastMs) / 1000)
                hour = calendar.component(.hour, from: lastRun)
                minute = calendar.component(.minute, from: lastRun)
            }

            let types = rule.scheduleJobTypes ?? []
            let fixedWeekdays = types.compactMap { t -> Int? in
                guard t.hasPrefix("DAY_OF_WEEK_"), let n = Int(t.dropFirst("DAY_OF_WEEK_".count)) else { return nil }
                return n + 1
            }

            if !fixedWeekdays.isEmpty {
                for offset in 0..<8 {
                    guard let candidate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                    let weekday = calendar.component(.weekday, from: candidate)
                    guard fixedWeekdays.contains(weekday) else { continue }
                    var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
                    comps.hour = hour; comps.minute = minute; comps.second = 0
                    if let runDate = calendar.date(from: comps), runDate > now {
                        candidates.append(runDate); break
                    }
                }
            } else {
                var intervalDays = 1
                for t in types {
                    if t.hasPrefix("INTERVAL_"), let n = Int(t.dropFirst("INTERVAL_".count)), n > 0 {
                        intervalDays = n; break
                    }
                }
                for offset in 0...intervalDays {
                    guard let candidate = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                    var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
                    comps.hour = hour; comps.minute = minute; comps.second = 0
                    if let runDate = calendar.date(from: comps), runDate > now {
                        candidates.append(runDate); break
                    }
                }
            }
        }
        return candidates.min()
    }
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
        case .httpError(429):
            return "Rachio API rate limit reached. Resets at midnight UTC."
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
    
    // Cache to avoid hammering Rachio API
    private var cachedDevices: [RachioDevice]? = nil
    private var cacheTimestamp: Date? = nil
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    private var activeFetchTask: Task<[RachioDevice], Error>? = nil
    private let fetchLock = OSAllocatedUnfairLock()
    
    // Cache personId and deviceIds to avoid repeated calls
    private var cachedPersonId: String? = nil
    private var cachedDeviceIds: [String]? = nil
    
    // Rate limit state (public for UI)
    private(set) var rateLimitedUntil: Date? = nil
    private(set) var rateLimitRemaining: Int? = nil
    private(set) var rateLimitTotal: Int? = nil
    private let rateLimitBackoff: TimeInterval = 300 // 5 minutes fallback

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

    // MARK: - Rate Limit Logging
    
    private func logRateLimitHeaders(_ response: HTTPURLResponse, endpoint: String) {
        let headers = response.allHeaderFields
        var info: [String] = []
        
        // Common rate limit header names
        for key in ["X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset", 
                    "RateLimit-Limit", "RateLimit-Remaining", "RateLimit-Reset",
                    "Retry-After", "X-Retry-After"] {
            if let value = headers[key] ?? headers[key.lowercased()] {
                info.append("\(key): \(value)")
            }
        }
        
        if !info.isEmpty {
            logger.debug(" \(endpoint) rate headers: \(info.joined(separator: ", "))")
        } else if response.statusCode == 429 {
            logger.debug(" \(endpoint) 429 - all headers: \(headers)")
        }
        
        // Parse rate limit values (headers might have different casing)
        let headerDict = Dictionary(uniqueKeysWithValues: headers.map { (String(describing: $0.key).lowercased(), $0.value) })
        
        if let limitStr = headerDict["x-ratelimit-limit"] as? String, let limit = Int(limitStr) {
            rateLimitTotal = limit
        }
        if let remainStr = headerDict["x-ratelimit-remaining"] as? String, let remain = Int(remainStr) {
            rateLimitRemaining = remain
        }
        if let resetStr = headerDict["x-ratelimit-reset"] as? String {
            let formatter = ISO8601DateFormatter()
            if let resetDate = formatter.date(from: resetStr) {
                if response.statusCode == 429 || rateLimitRemaining == 0 {
                    rateLimitedUntil = resetDate
                    let mins = Int(resetDate.timeIntervalSinceNow / 60)
                    logger.debug(" Rate limited until \(resetStr) (\(mins) min from now)")
                }
            }
        }
    }
    
    /// Check if currently rate limited
    var isRateLimited: Bool {
        guard let until = rateLimitedUntil else { return false }
        return Date() < until
    }
    
    /// Minutes until rate limit resets (nil if not limited)
    var rateLimitResetsInMinutes: Int? {
        guard let until = rateLimitedUntil, Date() < until else { return nil }
        return max(1, Int(until.timeIntervalSinceNow / 60))
    }

    // MARK: - Get Person Info

    private func getPersonId() async throws -> String {
        // Return cached personId if available
        if let cached = cachedPersonId {
            return cached
        }
        
        let request = try makeRequest(path: "/person/info")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }
        
        // Log rate limit headers
        logRateLimitHeaders(httpResponse, endpoint: "/person/info")
        
        guard httpResponse.statusCode == 200 else {
            throw RachioAPIError.httpError(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(RachioPersonInfoResponse.self, from: data)
            cachedPersonId = decoded.id
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
            let device = try JSONDecoder().decode(RachioDevice.self, from: data)

            return device
        } catch {
            throw RachioAPIError.decodingError(error)
        }
    }
    
    // MARK: - Get Schedule Rules for Device



    // MARK: - Get Devices

    func getDevices(forceRefresh: Bool = false) async throws -> [RachioDevice] {
        // If we're rate-limited, fail fast or return stale cache
        if let until = rateLimitedUntil, Date() < until {
            let waitSecs = Int(until.timeIntervalSince(Date()))
            logger.debug(" rate-limited, \(waitSecs)s remaining")
            if let cached = cachedDevices {
                return cached // return stale cache rather than error
            }
            throw RachioAPIError.httpError(429)
        }
        
        // Return cached if fresh enough (no lock needed for read)
        if !forceRefresh,
           let cached = cachedDevices,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheTTL {
            logger.debug(" returning cached devices (\(Int(Date().timeIntervalSince(ts)))s old)")
            return cached
        }
        
        // Thread-safe check for existing fetch task
        let existingTask: Task<[RachioDevice], Error>? = fetchLock.withLock { activeFetchTask }
        if let existing = existingTask {
            logger.debug(" getDevices: fetch in progress, waiting for existing task...")
            return try await existing.value
        }
        
        logger.debug(" getDevices: starting new fetch task")
        // Start new fetch task
        let task = Task<[RachioDevice], Error> { [weak self] in
            guard let self else { throw RachioAPIError.invalidResponse }
            defer { 
                self.fetchLock.withLock { self.activeFetchTask = nil }
                logger.debug(" getDevices: fetch task completed, cleared activeFetchTask")
            }
            do {
                let result = try await fetchDevicesFromAPI()
                rateLimitedUntil = nil // clear any backoff on success
                return result
            } catch RachioAPIError.httpError(429) {
                // Only use fallback if header didn't set a reset time
                logger.debug(" got 429, rateLimitedUntil=\(String(describing: rateLimitedUntil))")
                if rateLimitedUntil == nil || rateLimitedUntil! < Date() {
                    logger.debug(" no valid reset time from header, backing off for 5 min")
                    rateLimitedUntil = Date().addingTimeInterval(rateLimitBackoff)
                }
                throw RachioAPIError.httpError(429)
            }
        }
        fetchLock.withLock { activeFetchTask = task }
        
        return try await task.value
    }
    
    private func fetchDevicesFromAPI() async throws -> [RachioDevice] {
        let personId = try await getPersonId()
        logger.debug(" personId: \(personId)")

        // Use in-memory cache, then try API, then Keychain fallback
        let deviceIds: [String]
        if let cached = cachedDeviceIds, !cached.isEmpty {
            deviceIds = cached
        } else if let ids = try? await fetchDeviceIds(personId: personId), !ids.isEmpty {
            cachedDeviceIds = ids
            _ = try? KeychainService.shared.save(ids.joined(separator: ","), forKey: KeychainKey.rachioDeviceIds)
            deviceIds = ids
        } else if let keychain = KeychainService.shared.load(forKey: KeychainKey.rachioDeviceIds),
                  !keychain.isEmpty {
            let ids = keychain.split(separator: ",").map(String.init)
            cachedDeviceIds = ids
            deviceIds = ids
        } else {
            throw RachioAPIError.apiError("Could not discover Rachio devices. Try saving your API key and testing the connection again.")
        }
        logger.debug(" deviceIds: \(deviceIds)")

        var devices: [RachioDevice] = []
        for id in deviceIds {
            let device = try await fetchDevice(id: id)
            logger.debug(" fetched device: \(device.name), \(device.scheduleRules?.count ?? 0) schedules")
            devices.append(device)
        }
        
        // Cache result
        cachedDevices = devices
        cacheTimestamp = Date()
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

    // MARK: - Watering Events

    private var cachedEvents: [RachioWateringEvent]? = nil
    private var eventCacheTimestamp: Date? = nil

    /// Fetch watering events for a device for the past N days (cached 10 min).
    func getWateringEvents(deviceId: String, days: Int = 7, forceRefresh: Bool = false) async throws -> [RachioWateringEvent] {
        if !forceRefresh,
           let cached = cachedEvents,
           let ts = eventCacheTimestamp,
           Date().timeIntervalSince(ts) < 600 {
            return cached
        }

        let endMs = Int(Date().timeIntervalSince1970 * 1000)
        let startMs = endMs - (days * 86400 * 1000)
        let request = try makeRequest(path: "/device/\(deviceId)/event?startTime=\(startMs)&endTime=\(endMs)", method: "GET")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RachioAPIError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let events: [RachioWateringEvent] = json.compactMap { dict in
            guard let type = dict["type"] as? String, type == "ZONE_STATUS",
                  let subType = dict["subType"] as? String, subType == "ZONE_STARTED",
                  let eventDateMs = dict["eventDate"] as? Int,
                  let zoneId = dict["zoneId"] as? String,
                  let zoneName = dict["zoneName"] as? String,
                  let duration = dict["duration"] as? Int,
                  let id = dict["id"] as? String else { return nil }
            let startDate = Date(timeIntervalSince1970: Double(eventDateMs) / 1000)
            return RachioWateringEvent(id: id, zoneId: zoneId, zoneName: zoneName, startDate: startDate, duration: duration)
        }

        cachedEvents = events
        eventCacheTimestamp = Date()
        logger.info("Fetched \(events.count) watering events for device \(deviceId)")
        return events
    }
}
