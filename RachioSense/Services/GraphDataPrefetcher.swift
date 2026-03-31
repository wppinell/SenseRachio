import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.rachiosense", category: "GraphPrefetch")

/// Fetches sensor history from SenseCAP and stores in SwiftData.
@MainActor
final class GraphDataPrefetcher {
    static let shared = GraphDataPrefetcher()

    private var activeFetchTask: Task<Void, Never>?
    private var isFetching = false  // Simple lock to prevent concurrent fetches
    private var lastFullFetchAt: Date? = nil  // Cooldown for force refresh
    private let lastIncrementalFetchKey = "lastIncrementalFetchTimestamp"

    private init() {}

    // MARK: - Public API

    /// Fetch only data since the most recent reading — smart refresh
    func fetchRecent(modelContext: ModelContext) async {
        if isFetching {
            logger.debug(" fetchRecent: already fetching, skipping")
            return
        }
        
        // Find the most recent reading we have
        let readings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        let latestReading = readings.max(by: { $0.recordedAt < $1.recordedAt })
        
        let hours: Int
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        
        if let latest = latestReading {
            // Fetch from last reading to now, plus 1 hour buffer
            let gap = Date().timeIntervalSince(latest.recordedAt) / 3600
            hours = max(1, Int(ceil(gap)) + 1)
            let rangeStart = Date().addingTimeInterval(-Double(hours) * 3600)
            logger.debug(" 📊 Status: \(readings.count) readings cached")
            logger.debug(" 📊 Latest reading: \(formatter.string(from: latest.recordedAt)) (\(String(format: "%.1f", gap))h ago)")
            logger.debug(" 📊 Requesting: \(hours)h of data (\(formatter.string(from: rangeStart)) → now)")
        } else {
            // No data — fetch full 7 days
            hours = 168
            let rangeStart = Date().addingTimeInterval(-Double(hours) * 3600)
            logger.debug(" 📊 Status: NO CACHED DATA")
            logger.debug(" 📊 Requesting: full \(hours)h (\(formatter.string(from: rangeStart)) → now)")
        }
        
        await run(modelContext: modelContext, hours: hours)
    }
    
    /// Fetch full 7-day history — use sparingly (e.g., first launch, reset cache)
    func forceFull(modelContext: ModelContext) async {
        // If already fetching, skip
        if isFetching {
            logger.debug(" forceFull: already fetching, skipping")
            return
        }
        
        // Cooldown: don't allow full refresh more than once per 30 seconds
        if let last = lastFullFetchAt, Date().timeIntervalSince(last) < 30 {
            logger.debug(" forceFull: cooldown active, skipping (wait \(30 - Int(Date().timeIntervalSince(last)))s)")
            return
        }
        
        activeFetchTask?.cancel()
        activeFetchTask = nil
        UserDefaults.standard.removeObject(forKey: lastIncrementalFetchKey)
        lastFullFetchAt = Date()

        await run(modelContext: modelContext, hours: 168)
    }


    /// Fetch since last fetch (or 7 days if first time). Skips if fetched < 5 min ago.
    func fetchIfNeeded(modelContext: ModelContext) async {
        if isFetching {
            logger.debug(" fetchIfNeeded: already fetching, waiting...")
            while isFetching {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            return
        }

        let now = Date()
        let lastFetch = UserDefaults.standard.object(forKey: lastIncrementalFetchKey) as? Date
        let allReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        let existingCount = allReadings.count

        // Check per-sensor: find any sensor with < 6.5 days coverage
        let sensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []
        let visibleEUIs = Set(sensors.filter { !$0.isHiddenFromGraphs }.map(\.eui))
        let readingsByEUI = Dictionary(grouping: allReadings.filter { visibleEUIs.contains($0.eui) }, by: \.eui)
        let sevenDaysAgo = now.addingTimeInterval(-168 * 3600)
        
        var sensorsNeedingFetch: [String] = []
        for eui in visibleEUIs {
            let readings = readingsByEUI[eui] ?? []
            let oldest = readings.min(by: { $0.recordedAt < $1.recordedAt })?.recordedAt
            if oldest == nil || oldest! > sevenDaysAgo.addingTimeInterval(12 * 3600) { // Missing data older than 6.5 days
                sensorsNeedingFetch.append(String(eui.suffix(4)))
            }
        }

        // Always fetch full 7 days if: no data, no prior fetch, or any sensor has incomplete coverage
        guard let last = lastFetch, existingCount > 0, sensorsNeedingFetch.isEmpty else {
            if !sensorsNeedingFetch.isEmpty {
                logger.info("Sensors with incomplete history: \(sensorsNeedingFetch.joined(separator: ", ")) — fetching full 7 days")
            } else {
                logger.info("First run or empty DB — fetching full 7 days")
            }
            await run(modelContext: modelContext, hours: 168)
            return
        }

        // Skip if fetched < 5 min ago
        let gap = now.timeIntervalSince(last)
        if gap < 300 {
            logger.debug(" Skipping — fetched \(Int(gap))s ago, \(existingCount) readings cached")
            return
        }

        // Fetch gap since last fetch, minimum 1h, maximum 7 days
        let hours = max(1, min(168, Int(ceil(gap / 3600)) + 1))
        await run(modelContext: modelContext, hours: hours)
    }

    // MARK: - Core Fetch

    private func run(modelContext: ModelContext, hours: Int) async {
        // Acquire lock
        guard !isFetching else {
            logger.debug(" run() skipped — already fetching")
            return
        }
        isFetching = true
        defer { isFetching = false }
        
        let now = Date()

        // Verify credentials before fetching
        guard let apiKey = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey),
              let apiSecret = KeychainService.shared.load(forKey: KeychainKey.senseCraftAPISecret),
              !apiKey.isEmpty, !apiSecret.isEmpty else {
            logger.warning("No SenseCraft credentials — aborting history fetch")
            return
        }
        logger.info("Starting history fetch: \(hours)h, key=\(apiKey.prefix(6))…")

        let allSensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []
        logger.debug(" Total sensors in DB: \(allSensors.count)")
        let visibleSensors = allSensors.filter { !$0.isHiddenFromGraphs }
        logger.debug(" Visible sensors: \(visibleSensors.count) — EUIs: \(visibleSensors.map { $0.eui }.joined(separator: ", "))")
        guard !visibleSensors.isEmpty else {
            logger.debug(" ABORTING — no visible sensors!")
            return
        }

        logger.debug(" Fetching \(hours)h for \(visibleSensors.count) sensors")

        // Build dedup set from existing readings
        let existingReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var existingByEUI: [String: Set<Date>] = [:]
        for r in existingReadings {
            existingByEUI[r.eui, default: []].insert(r.recordedAt)
        }

        // Fetch sensors one at a time to avoid 429s
        var allResults: [(String, [SenseCraftAPI.HistoricalReading])] = []
        for (i, sensor) in visibleSensors.enumerated() {
            if i > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) } // 2s between sensors
            let result = await fetchWithRetry(sensor: sensor, hours: hours)
            allResults.append(result)
            logger.info("Sensor \(i+1)/\(visibleSensors.count): \(sensor.eui.suffix(4)) = \(result.1.count) readings")
        }
        logger.debug(" Total fetched: \(allResults.map { $0.1.count }.reduce(0, +)) readings across \(allResults.count) sensors")

        // Insert on MainActor
        var inserted = 0
        var skippedDupe = 0
        var skippedNoMoisture = 0
        for (eui, history) in allResults {
            let existing = existingByEUI[eui] ?? []
            for reading in history {
                let t = reading.timestamp.rounded(toMinutes: 1)
                guard let moisture = reading.moisture else {
                    skippedNoMoisture += 1
                    continue
                }
                // Skip obviously bad readings
                guard moisture >= 0 && moisture <= 100 else {
                    skippedNoMoisture += 1
                    continue
                }
                if existing.contains(where: { abs($0.timeIntervalSince(t)) < 60 }) {
                    skippedDupe += 1
                    continue
                }
                modelContext.insert(SensorReading(eui: eui, moisture: moisture, tempC: reading.tempC ?? 0, recordedAt: t))
                inserted += 1
            }
        }

        // Also purge any bad readings already in DB
        let badReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>()))?.filter {
            $0.moisture < 0 || $0.moisture > 100
        } ?? []
        if !badReadings.isEmpty {
            badReadings.forEach { modelContext.delete($0) }
            logger.info("Purged \(badReadings.count) out-of-range readings from DB")
        }
        logger.debug(" Inserted \(inserted) new, skipped \(skippedDupe) dupes, skipped \(skippedNoMoisture) no-moisture")

        do {
            try modelContext.save()
            logger.debug(" Save succeeded")
        } catch {
            logger.debug(" Save FAILED: \(error)")
        }

        // Prune > 7 days
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        let freshReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        let old = freshReadings.filter { $0.recordedAt < cutoff }
        if !old.isEmpty {
            old.forEach { modelContext.delete($0) }
            _ = try? modelContext.save()
            logger.debug(" Pruned \(old.count) old readings")
        }

        UserDefaults.standard.set(now, forKey: lastIncrementalFetchKey)
    }
    // MARK: - Retry Helper

    private func fetchWithRetry(sensor: SensorConfig, hours: Int) async -> (String, [SenseCraftAPI.HistoricalReading]) {
        let eui = sensor.eui
        do {
            let history = try await SenseCraftAPI.shared.fetchHistory(eui: eui, hours: hours)
            logger.debug("✓ \(eui.suffix(4)): \(history.count) readings")
            return (eui, history)
        } catch SenseCraftAPIError.httpError(429) {
            // Wait 10s and retry once
            logger.warning("429 on \(eui.suffix(4)) — retrying in 10s")
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            do {
                let history = try await SenseCraftAPI.shared.fetchHistory(eui: eui, hours: hours)
                logger.debug("✓ \(eui.suffix(4)) retry: \(history.count) readings")
                return (eui, history)
            } catch {
                logger.error("✗ \(eui.suffix(4)) retry failed: \(error.localizedDescription)")
                return (eui, [])
            }
        } catch {
            logger.error("✗ \(eui.suffix(4)): \(error.localizedDescription)")
            return (eui, [])
        }
    }
}

// MARK: - Date Extension

private extension Date {
    func rounded(toMinutes minutes: Int) -> Date {
        let s = Double(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / s).rounded() * s)
    }
}
