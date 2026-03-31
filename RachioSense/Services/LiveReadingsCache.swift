import Foundation
import SwiftData
import os

/// Shared cache for live sensor readings. Prevents duplicate API calls across ViewModels.
/// Uses an actor for thread-safe access.
actor LiveReadingsCache {
    static let shared = LiveReadingsCache()
    
    private static let logger = Logger(subsystem: "com.rachiosense", category: "LiveReadingsCache")
    
    private var readings: [String: CachedReading] = [:]
    private var lastFetchDate: Date? = nil
    private var isFetching = false
    private var fetchContinuations: [CheckedContinuation<[String: SensorReading], Never>] = []
    
    private let cacheTTL: TimeInterval = 60 // 1 minute cache validity
    
    struct CachedReading: Sendable {
        let eui: String
        let moisture: Double
        let tempC: Double
        let fetchedAt: Date
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Get cached readings if fresh, otherwise fetch new ones.
    /// Multiple callers will coalesce into a single fetch.
    /// Note: hiddenEuis is passed in from the caller (main actor) to avoid ModelContext threading issues.
    func getReadings(hiddenEuis: Set<String> = []) async -> [String: SensorReading] {
        // Return cached if still valid
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < cacheTTL,
           !readings.isEmpty {
            Self.logger.debug("Returning cached readings (\(self.readings.count) sensors)")
            return buildSensorReadings(from: readings)
        }
        
        // If already fetching, wait for result
        if isFetching {
            Self.logger.debug("Fetch in progress, waiting...")
            return await withCheckedContinuation { continuation in
                fetchContinuations.append(continuation)
            }
        }
        
        // Start new fetch
        isFetching = true
        Self.logger.info("Starting fresh sensor readings fetch")
        
        let newReadings = await performFetch(hiddenEuis: hiddenEuis)
        
        // Update cache
        readings = newReadings
        lastFetchDate = Date()
        isFetching = false
        
        let result = buildSensorReadings(from: newReadings)
        
        // Resume any waiting callers
        for continuation in fetchContinuations {
            continuation.resume(returning: result)
        }
        fetchContinuations.removeAll()
        
        Self.logger.info("Fetch complete, \(newReadings.count) readings cached")
        return result
    }
    
    /// Force a refresh on next access
    func invalidate() {
        lastFetchDate = nil
        Self.logger.debug("Cache invalidated")
    }
    
    /// Get the last fetch date
    func getLastFetchDate() -> Date? {
        lastFetchDate
    }
    
    // MARK: - Private
    
    private func performFetch(hiddenEuis: Set<String>) async -> [String: CachedReading] {
        guard KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) != nil else {
            Self.logger.warning("No SenseCraft credentials configured")
            return [:]
        }
        
        do {
            let devices = try await SenseCraftAPI.shared.listDevices()
            
            // Fetch readings concurrently
            let fetchedReadings: [CachedReading] = await withTaskGroup(of: CachedReading?.self) { group in
                for device in devices {
                    if hiddenEuis.contains(device.deviceEui) { continue }
                    
                    group.addTask {
                        do {
                            let r = try await SenseCraftAPI.shared.fetchReading(eui: device.deviceEui)
                            guard let moisture = r.moisture else { return nil }
                            return CachedReading(
                                eui: device.deviceEui,
                                moisture: moisture,
                                tempC: r.tempC ?? 0,
                                fetchedAt: Date()
                            )
                        } catch {
                            Self.logger.error("Failed to fetch reading for \(device.deviceEui): \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
                
                var results: [CachedReading] = []
                for await result in group {
                    if let r = result { results.append(r) }
                }
                return results
            }
            
            return Dictionary(uniqueKeysWithValues: fetchedReadings.map { ($0.eui, $0) })
        } catch {
            Self.logger.error("Failed to list devices: \(error.localizedDescription)")
            return [:]
        }
    }
    
    private nonisolated func buildSensorReadings(from cache: [String: CachedReading]) -> [String: SensorReading] {
        var result: [String: SensorReading] = [:]
        for (eui, cached) in cache {
            result[eui] = SensorReading(
                eui: cached.eui,
                moisture: cached.moisture,
                tempC: cached.tempC,
                recordedAt: cached.fetchedAt
            )
        }
        return result
    }
}
