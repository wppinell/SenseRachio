import Foundation
import SwiftData

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
            print("[Prefetch] fetchRecent: already fetching, skipping")
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
            print("[Refresh] 📊 Status: \(readings.count) readings cached")
            print("[Refresh] 📊 Latest reading: \(formatter.string(from: latest.recordedAt)) (\(String(format: "%.1f", gap))h ago)")
            print("[Refresh] 📊 Requesting: \(hours)h of data (\(formatter.string(from: rangeStart)) → now)")
        } else {
            // No data — fetch full 7 days
            hours = 168
            let rangeStart = Date().addingTimeInterval(-Double(hours) * 3600)
            print("[Refresh] 📊 Status: NO CACHED DATA")
            print("[Refresh] 📊 Requesting: full \(hours)h (\(formatter.string(from: rangeStart)) → now)")
        }
        
        await run(modelContext: modelContext, hours: hours)
    }
    
    /// Fetch full 7-day history — use sparingly (e.g., first launch, reset cache)
    func forceFull(modelContext: ModelContext) async {
        // If already fetching, skip
        if isFetching {
            print("[Prefetch] forceFull: already fetching, skipping")
            return
        }
        
        // Cooldown: don't allow full refresh more than once per 30 seconds
        if let last = lastFullFetchAt, Date().timeIntervalSince(last) < 30 {
            print("[Prefetch] forceFull: cooldown active, skipping (wait \(30 - Int(Date().timeIntervalSince(last)))s)")
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
        // If already fetching, wait for it instead of starting another
        if isFetching {
            print("[Prefetch] fetchIfNeeded: already fetching, waiting...")
            while isFetching {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            return
        }

        let now = Date()
        let lastFetch = UserDefaults.standard.object(forKey: lastIncrementalFetchKey) as? Date

        // Check if we actually have data — never skip if DB is empty
        let existingCount = (try? modelContext.fetch(FetchDescriptor<SensorReading>()))?.count ?? 0

        // Skip only if fetched recently AND we have data
        if let last = lastFetch, now.timeIntervalSince(last) < 300, existingCount > 0 {
            print("[Prefetch] Skipping — fetched \(Int(now.timeIntervalSince(last)))s ago, \(existingCount) readings cached")
            return
        }

        // Hours to fetch: gap since last fetch, or full 7 days (clean slate)
        let hours: Int
        if let last = lastFetch {
            hours = max(1, Int(ceil(now.timeIntervalSince(last) / 3600)))
        } else {
            hours = 168 // 7 days - first fetch
        }

        await run(modelContext: modelContext, hours: hours)
    }

    // MARK: - Core Fetch

    private func run(modelContext: ModelContext, hours: Int) async {
        // Acquire lock
        guard !isFetching else {
            print("[Prefetch] run() skipped — already fetching")
            return
        }
        isFetching = true
        defer { isFetching = false }
        
        let now = Date()

        let allSensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []
        print("[Prefetch] Total sensors in DB: \(allSensors.count)")
        let visibleSensors = allSensors.filter { !$0.isHiddenFromGraphs }
        print("[Prefetch] Visible sensors: \(visibleSensors.count) — EUIs: \(visibleSensors.map { $0.eui }.joined(separator: ", "))")
        guard !visibleSensors.isEmpty else {
            print("[Prefetch] ABORTING — no visible sensors!")
            return
        }

        print("[Prefetch] Fetching \(hours)h for \(visibleSensors.count) sensors")

        // Build dedup set from existing readings
        let existingReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var existingByEUI: [String: Set<Date>] = [:]
        for r in existingReadings {
            existingByEUI[r.eui, default: []].insert(r.recordedAt)
        }

        // Fetch sensors with limited concurrency (2 at a time) to avoid rate limits
        var allResults: [(String, [SenseCraftAPI.HistoricalReading])] = []
        let maxConcurrent = 2
        let batchCount = Int(ceil(Double(visibleSensors.count) / Double(maxConcurrent)))
        print("[Prefetch] Will fetch in \(batchCount) batches of \(maxConcurrent)")
        
        for batch in stride(from: 0, to: visibleSensors.count, by: maxConcurrent) {
            let batchNum = (batch / maxConcurrent) + 1
            let batchEnd = min(batch + maxConcurrent, visibleSensors.count)
            let batchSensors = Array(visibleSensors[batch..<batchEnd])
            print("[Prefetch] Batch \(batchNum)/\(batchCount): fetching \(batchSensors.map { $0.eui.suffix(4) }.joined(separator: ", "))")
            
            await withTaskGroup(of: (String, [SenseCraftAPI.HistoricalReading]).self) { group in
                for sensor in batchSensors {
                    group.addTask {
                        do {
                            let history = try await SenseCraftAPI.shared.fetchHistory(eui: sensor.eui, hours: hours)
                            print("[Prefetch] ✓ \(sensor.eui.suffix(4)): \(history.count) readings")
                            return (sensor.eui, history)
                        } catch {
                            print("[Prefetch] ✗ \(sensor.eui.suffix(4)): \(error.localizedDescription)")
                            return (sensor.eui, [])
                        }
                    }
                }
                for await result in group { allResults.append(result) }
            }
            print("[Prefetch] Batch \(batchNum) complete")
        }
        print("[Prefetch] Total fetched: \(allResults.map { $0.1.count }.reduce(0, +)) readings across \(allResults.count) sensors")

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
                if existing.contains(where: { abs($0.timeIntervalSince(t)) < 60 }) {
                    skippedDupe += 1
                    continue
                }
                modelContext.insert(SensorReading(eui: eui, moisture: moisture, tempC: reading.tempC ?? 0, recordedAt: t))
                inserted += 1
            }
        }
        print("[Prefetch] Inserted \(inserted) new, skipped \(skippedDupe) dupes, skipped \(skippedNoMoisture) no-moisture")

        do {
            try modelContext.save()
            print("[Prefetch] Save succeeded")
        } catch {
            print("[Prefetch] Save FAILED: \(error)")
        }

        // Prune > 7 days
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        let freshReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        let old = freshReadings.filter { $0.recordedAt < cutoff }
        if !old.isEmpty {
            old.forEach { modelContext.delete($0) }
            _ = try? modelContext.save()
            print("[Prefetch] Pruned \(old.count) old readings")
        }

        UserDefaults.standard.set(now, forKey: lastIncrementalFetchKey)
    }
}

// MARK: - Date Extension

private extension Date {
    func rounded(toMinutes minutes: Int) -> Date {
        let s = Double(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / s).rounded() * s)
    }
}
