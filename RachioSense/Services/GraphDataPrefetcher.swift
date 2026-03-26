import Foundation
import SwiftData

/// Fetches sensor history from SenseCAP and stores in SwiftData.
@MainActor
final class GraphDataPrefetcher {
    static let shared = GraphDataPrefetcher()

    private var activeFetchTask: Task<Void, Never>?
    private let lastIncrementalFetchKey = "lastIncrementalFetchTimestamp"

    private init() {}

    // MARK: - Public API

    /// Fetch full 7-day history — deletes existing readings first, then re-fetches clean.
    func forceFull(modelContext: ModelContext) async {
        activeFetchTask?.cancel()
        activeFetchTask = nil
        UserDefaults.standard.removeObject(forKey: lastIncrementalFetchKey)

        let all = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        all.forEach { modelContext.delete($0) }
        _ = try? modelContext.save()

        await run(modelContext: modelContext, hours: 168) // 7 days standard
    }

    /// Fetch extra week on-demand (only when 2w is selected). Skips if already have 2w data.
    func fetchExtendedIfNeeded(modelContext: ModelContext) async {
        let key = "lastExtendedFetchTimestamp"
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           now.timeIntervalSince(last) < 3600 { return } // skip if fetched within 1h

        // Only fetch days 8-14 (hours 168-336)
        let allSensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []
        let visibleSensors = allSensors.filter { !$0.isHiddenFromGraphs }
        guard !visibleSensors.isEmpty else { return }

        print("[Prefetch] Fetching extended 2w window (days 8-14)")

        let existingReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var existingByEUI: [String: Set<Date>] = [:]
        for r in existingReadings { existingByEUI[r.eui, default: []].insert(r.recordedAt) }

        let nowMs = Int(now.timeIntervalSince1970 * 1000)

        await withTaskGroup(of: (String, [SenseCraftAPI.HistoricalReading]).self) { group in
            for sensor in visibleSensors {
                group.addTask {
                    var readings: [SenseCraftAPI.HistoricalReading] = []
                    // Fetch days 8-14 in 24h chunks
                    for day in 7..<14 {
                        let endMs   = nowMs - (day * 86400 * 1000)
                        let startMs = endMs - (86400 * 1000)
                        if let chunk = try? await SenseCraftAPI.shared.fetchHistoryChunk(eui: sensor.eui, startMs: startMs, endMs: endMs) {
                            readings.append(contentsOf: chunk)
                        }
                    }
                    return (sensor.eui, readings)
                }
            }

            var inserted = 0
            for await (eui, history) in group {
                let existing = existingByEUI[eui] ?? []
                for reading in history {
                    let t = reading.timestamp.rounded(toMinutes: 1)
                    guard let moisture = reading.moisture else { continue }
                    if existing.contains(where: { abs($0.timeIntervalSince(t)) < 60 }) { continue }
                    modelContext.insert(SensorReading(eui: eui, moisture: moisture, tempC: reading.tempC ?? 0, recordedAt: t))
                    inserted += 1
                }
            }
            print("[Prefetch] Extended: inserted \(inserted) readings")
        }

        _ = try? modelContext.save()
        UserDefaults.standard.set(now, forKey: key)
    }

    /// Fetch since last fetch (or 7 days if first time). Skips if fetched < 5 min ago.
    func fetchIfNeeded(modelContext: ModelContext) async {
        // If a fetch is running, wait for it
        if let existing = activeFetchTask {
            await existing.value
            return
        }

        let now = Date()
        let lastFetch = UserDefaults.standard.object(forKey: lastIncrementalFetchKey) as? Date

        // Skip if very recent
        if let last = lastFetch, now.timeIntervalSince(last) < 300 {
            print("[Prefetch] Skipping — fetched \(Int(now.timeIntervalSince(last)))s ago")
            return
        }

        // Hours to fetch: gap since last fetch, or full 7 days (clean slate)
        let hours: Int
        if let last = lastFetch {
            hours = max(1, Int(ceil(now.timeIntervalSince(last) / 3600)))
        } else {
            // First ever fetch — clear any stale data and fetch full 7 days
            let stale = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
            stale.forEach { modelContext.delete($0) }
            _ = try? modelContext.save()
            hours = 168 // 7 days
        }

        let task = Task { await self.run(modelContext: modelContext, hours: hours) }
        activeFetchTask = task
        await task.value
        activeFetchTask = nil
    }

    // MARK: - Core Fetch

    private func run(modelContext: ModelContext, hours: Int) async {
        let now = Date()

        let allSensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []
        let visibleSensors = allSensors.filter { !$0.isHiddenFromGraphs }
        guard !visibleSensors.isEmpty else { return }

        print("[Prefetch] Fetching \(hours)h for \(visibleSensors.count) sensors")

        // Build dedup set from existing readings
        let existingReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var existingByEUI: [String: Set<Date>] = [:]
        for r in existingReadings {
            existingByEUI[r.eui, default: []].insert(r.recordedAt)
        }

        // Fetch all sensors in parallel
        await withTaskGroup(of: (String, [SenseCraftAPI.HistoricalReading]).self) { group in
            for sensor in visibleSensors {
                group.addTask {
                    do {
                        let history = try await SenseCraftAPI.shared.fetchHistory(eui: sensor.eui, hours: hours)
                        return (sensor.eui, history)
                    } catch {
                        print("[Prefetch] Failed \(sensor.eui): \(error.localizedDescription)")
                        return (sensor.eui, [])
                    }
                }
            }

            var inserted = 0
            for await (eui, history) in group {
                let existing = existingByEUI[eui] ?? []
                for reading in history {
                    let t = reading.timestamp.rounded(toMinutes: 1)
                    guard let moisture = reading.moisture else { continue }
                    // Skip if we already have a reading within 60s
                    if existing.contains(where: { abs($0.timeIntervalSince(t)) < 60 }) { continue }
                    modelContext.insert(SensorReading(eui: eui, moisture: moisture, tempC: reading.tempC ?? 0, recordedAt: t))
                    inserted += 1
                }
            }
            print("[Prefetch] Inserted \(inserted) new readings")
        }

        _ = try? modelContext.save()

        // Prune > 7 days
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        let old = existingReadings.filter { $0.recordedAt < cutoff }
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
