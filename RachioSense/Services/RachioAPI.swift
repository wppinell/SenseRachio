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

struct RachioRainSkip: Identifiable {
    let id: String
    let scheduleName: String
    let skipDate: Date
    let reason: String  // e.g. "Rain detected", "Freeze detected"
}

struct RachioWateringEvent: Identifiable {
    let id: String
    let zoneId: String
    let zoneName: String
    let startDate: Date
    let endDate: Date?   // nil if only start event found
    let duration: Int    // seconds

    var isLongEnough: Bool { duration >= 300 } // 5 min minimum for fill
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
// Implemented as an actor to guarantee thread-safe access to all mutable state
// without manual locking. All stored properties are actor-isolated by default.

actor RachioAPI {
    static let shared = RachioAPI()

    private let baseURL = "https://api.rach.io/1/public"
    private let session: URLSession

    // Device cache — actor isolation ensures safe concurrent access
    private var cachedDevices: [RachioDevice]? = nil
    private var cacheTimestamp: Date? = nil
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    private var activeFetchTask: Task<[RachioDevice], Error>? = nil

    // Persisted IDs to reduce API calls across sessions
    private var cachedPersonId: String? = nil
    private var cachedDeviceIds: [String]? = nil

    // Rate limit state (readable from outside via actor hop)
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
        if let cached = cachedPersonId {
            return cached
        }

        let request = try makeRequest(path: "/person/info")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RachioAPIError.invalidResponse
        }

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
            return try JSONDecoder().decode(RachioDevice.self, from: data)
        } catch {
            throw RachioAPIError.decodingError(error)
        }
    }

    // MARK: - Get Devices

    func getDevices(forceRefresh: Bool = false) async throws -> [RachioDevice] {
        // If we're rate-limited, return stale cache or throw
        if let until = rateLimitedUntil, Date() < until {
            let waitSecs = Int(until.timeIntervalSince(Date()))
            logger.debug(" rate-limited, \(waitSecs)s remaining")
            if let cached = cachedDevices {
                return cached
            }
            throw RachioAPIError.httpError(429)
        }

        // Return cached if fresh enough
        if !forceRefresh,
           let cached = cachedDevices,
           let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) < cacheTTL {
            logger.debug(" returning cached devices (\(Int(Date().timeIntervalSince(ts)))s old)")
            return cached
        }

        // Coalesce concurrent callers onto the same in-flight Task
        if let existing = activeFetchTask {
            logger.debug(" getDevices: fetch in progress, waiting for existing task...")
            return try await existing.value
        }

        logger.debug(" getDevices: starting new fetch task")
        let task = Task<[RachioDevice], Error> {
            defer { self.activeFetchTask = nil }
            do {
                let result = try await self.fetchDevicesFromAPI()
                self.rateLimitedUntil = nil // clear any backoff on success
                return result
            } catch RachioAPIError.httpError(429) {
                logger.debug(" got 429, rateLimitedUntil=\(String(describing: self.rateLimitedUntil))")
                if self.rateLimitedUntil == nil || self.rateLimitedUntil! < Date() {
                    logger.debug(" no valid reset time from header, backing off for 5 min")
                    self.rateLimitedUntil = Date().addingTimeInterval(self.rateLimitBackoff)
                }
                throw RachioAPIError.httpError(429)
            }
        }
        activeFetchTask = task
        return try await task.value
    }

    private func fetchDevicesFromAPI() async throws -> [RachioDevice] {
        let personId = try await getPersonId()
        logger.debug(" personId: \(personId)")

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
            logger.warning("Watering events: unexpected response format: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")")
            return []
        }

        struct RawEvent {
            let id: String; let zoneName: String; let date: Date; let subType: String
        }
        let rawEvents: [RawEvent] = json.compactMap { dict in
            guard let type = dict["type"] as? String, type == "ZONE_STATUS",
                  let subType = dict["subType"] as? String,
                  (subType == "ZONE_STARTED" || subType == "ZONE_COMPLETED"),
                  let eventDateMs = dict["eventDate"] as? Int,
                  let id = dict["id"] as? String else { return nil }
            let summary = dict["summary"] as? String ?? ""
            let separators = [" began ", " started ", " completed ", " finished "]
            let zoneName = separators
                .compactMap { sep -> String? in
                    let parts = summary.components(separatedBy: sep)
                    return parts.count > 1 ? parts[0] : nil
                }
                .first?
                .trimmingCharacters(in: .whitespaces) ?? summary
            return RawEvent(id: id, zoneName: zoneName,
                            date: Date(timeIntervalSince1970: Double(eventDateMs) / 1000),
                            subType: subType)
        }

        let started   = rawEvents.filter { $0.subType == "ZONE_STARTED" }
        let completed = rawEvents.filter { $0.subType == "ZONE_COMPLETED" }
        logger.info("Parsed \(started.count) ZONE_STARTED, \(completed.count) ZONE_COMPLETED events")

        var events: [RachioWateringEvent] = started.map { s in
            let match = completed.filter { $0.zoneName == s.zoneName && $0.date > s.date }
                                 .min(by: { $0.date < $1.date })
            let duration = match.map { Int($0.date.timeIntervalSince(s.date)) } ?? 0
            return RachioWateringEvent(id: s.id, zoneId: "", zoneName: s.zoneName,
                                      startDate: s.date, endDate: match?.date, duration: duration)
        }

        if events.isEmpty {
            events = completed.map { c in
                RachioWateringEvent(id: c.id, zoneId: "", zoneName: c.zoneName,
                                   startDate: c.date, endDate: nil, duration: 0)
            }
        }

        // Deduplicate: collapse same zone within 2 hours
        let deduped = events.reduce(into: [RachioWateringEvent]()) { result, event in
            if result.contains(where: {
                $0.zoneName == event.zoneName &&
                abs($0.startDate.timeIntervalSince(event.startDate)) < 7200
            }) { return }
            result.append(event)
        }

        for e in deduped.prefix(3) {
            logger.info("Event: \(e.zoneName) start=\(e.startDate) end=\(e.endDate.map { "\($0)" } ?? "nil") duration=\(e.duration)s")
        }

        cachedEvents = deduped
        eventCacheTimestamp = Date()
        logger.info("Fetched \(events.count) watering events for device \(deviceId)")
        return deduped
    }

    /// Fetch weather intelligence skips (rain delay, freeze skip, etc.) — past and future
    func getRainSkips(deviceId: String, days: Int = 7) async throws -> [RachioRainSkip] {
        return try await getPastRainSkips(deviceId: deviceId, days: days)
    }

    /// Fetch rain skips from event history (past and near-future that are already decided)
    private func getPastRainSkips(deviceId: String, days: Int) async throws -> [RachioRainSkip] {
        let now = Date().timeIntervalSince1970 * 1000
        let startMs = Int(now) - (days * 86400 * 1000)
        // Look 2 days ahead for already-decided future skips
        let endMs = Int(now) + (2 * 86400 * 1000)
        let request = try makeRequest(path: "/device/\(deviceId)/event?startTime=\(startMs)&endTime=\(endMs)", method: "GET")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let skips: [RachioRainSkip] = json.compactMap { dict in
            guard let type = dict["type"] as? String,
                  let subType = dict["subType"] as? String,
                  let eventDateMs = dict["eventDate"] as? Int,
                  let id = dict["id"] as? String else { return nil }

            let isWeatherSkip = type == "WEATHER_INTELLIGENCE" && (subType.contains("SKIP") || subType.contains("DELAY"))
            guard isWeatherSkip else { return nil }

            let summary = dict["summary"] as? String ?? "Schedule skipped"

            let scheduleName: String
            if let range = summary.range(of: " was scheduled") {
                scheduleName = String(summary[..<range.lowerBound])
            } else if let range = summary.range(of: " schedule") {
                scheduleName = String(summary[..<range.lowerBound])
            } else {
                scheduleName = "Schedule"
            }
            let reason = subType.contains("RAIN") ? "Rain detected" :
                         subType.contains("FREEZE") ? "Freeze detected" :
                         subType.contains("WIND") ? "High wind" : "Weather skip"

            var skipDate = Date(timeIntervalSince1970: Double(eventDateMs) / 1000)
            if let forRange = summary.range(of: "for "),
               let atRange = summary.range(of: " at ", range: forRange.upperBound..<summary.endIndex) {
                let dateStr = String(summary[forRange.upperBound..<atRange.lowerBound])
                let timeStart = atRange.upperBound
                if let parenRange = summary.range(of: " (", range: timeStart..<summary.endIndex) {
                    let timeStr = String(summary[timeStart..<parenRange.lowerBound])
                    let fullStr = "\(dateStr) \(timeStr)"
                    let fmt = DateFormatter()
                    fmt.dateFormat = "M/d h:mm a"
                    fmt.defaultDate = Date()
                    if let parsed = fmt.date(from: fullStr) {
                        let cal = Calendar.current
                        var comps = cal.dateComponents([.month, .day, .hour, .minute], from: parsed)
                        comps.year = cal.component(.year, from: Date())
                        if let adjusted = cal.date(from: comps) {
                            skipDate = adjusted
                        }
                    }
                }
            }

            return RachioRainSkip(
                id: id,
                scheduleName: scheduleName.trimmingCharacters(in: .whitespaces),
                skipDate: skipDate,
                reason: reason
            )
        }

        logger.info("Found \(skips.count) past weather intelligence skips")
        return skips
    }
}
