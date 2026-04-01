import Foundation
import SwiftData
import Observation
import os

@Observable
final class SensorsViewModel {
    private static let logger = Logger(subsystem: "com.rachiosense", category: "SensorsViewModel")
    
    var sensors: [SensorConfig] = []
    var readings: [String: SensorReading] = [:]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    private var lastLoadedAt: Date? = nil
    private let reloadInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Load Sensors

    @MainActor
    func loadSensors(modelContext: ModelContext, forceRefresh: Bool = false) async {
        // Skip if recently loaded
        if !forceRefresh, let last = lastLoadedAt, Date().timeIntervalSince(last) < reloadInterval, !sensors.isEmpty {
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            let devices = try await SenseCraftAPI.shared.listDevices()

            // Upsert sensor configs in SwiftData
            let descriptor = FetchDescriptor<SensorConfig>()
            let existingConfigs = (try? modelContext.fetch(descriptor)) ?? []
            let existingByEui = Dictionary(uniqueKeysWithValues: existingConfigs.map { ($0.eui, $0) })

            var updatedConfigs: [SensorConfig] = []

            for device in devices {
                if let existing = existingByEui[device.deviceEui] {
                    existing.name = device.deviceName
                    existing.subscriptionExpiryDate = device.expiryDate
                    updatedConfigs.append(existing)
                } else {
                    let newConfig = SensorConfig(
                        id: device.deviceEui,
                        name: device.deviceName,
                        eui: device.deviceEui,
                        subscriptionExpiryDate: device.expiryDate
                    )
                    modelContext.insert(newConfig)
                    updatedConfigs.append(newConfig)
                }
            }

            try? modelContext.save()

            // Load existing latest readings from SwiftData as fallback
            let allStored = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
            var storedLatest: [String: SensorReading] = [:]
            for r in allStored {
                if let existing = storedLatest[r.eui] {
                    if r.recordedAt > existing.recordedAt { storedLatest[r.eui] = r }
                } else {
                    storedLatest[r.eui] = r
                }
            }

            // Use shared cache to prevent duplicate API calls
            let hiddenEuis = Set(updatedConfigs.filter { $0.isHiddenFromGraphs }.map { $0.eui })
        let cachedReadings = await LiveReadingsCache.shared.getReadings(hiddenEuis: hiddenEuis)
            
            // Merge: use cached/fresh reading if available, fall back to stored
            var newReadings: [String: SensorReading] = storedLatest
            
            for (eui, reading) in cachedReadings {
                // Also persist to SwiftData
                modelContext.insert(SensorReading(
                    eui: reading.eui,
                    moisture: reading.moisture,
                    tempC: reading.tempC,
                    recordedAt: reading.recordedAt
                ))
                newReadings[eui] = reading
            }
            _ = try? modelContext.save()
            
            // Create moisture lookup for sorting
            let moistureLookup = Dictionary(uniqueKeysWithValues: newReadings.map { ($0.key, $0.value.moisture) })
            
            // Sort sensors by moisture ascending (driest first)
            let sortedConfigs = updatedConfigs.sorted { a, b in
                let moistureA = moistureLookup[a.eui] ?? Double.infinity
                let moistureB = moistureLookup[b.eui] ?? Double.infinity
                return moistureA < moistureB
            }

            self.sensors = sortedConfigs
            self.readings = newReadings
            self.lastLoadedAt = Date()
            self.isLoading = false
        } catch {
            Self.logger.error("Failed to load sensors: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: - Predictive Dry Date

    /// Estimate when a sensor will hit the dry threshold based on recent decline rate.
    /// Uses readings from the last 24h, returns nil if trending up or insufficient data.
    func predictedDryDate(for eui: String, dryThreshold: Double, modelContext: ModelContext) -> Date? {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let descriptor = FetchDescriptor<SensorReading>(
            predicate: #Predicate { $0.eui == eui && $0.recordedAt > cutoff },
            sortBy: [SortDescriptor(\SensorReading.recordedAt)]
        )
        var recent = (try? modelContext.fetch(descriptor)) ?? []
        guard recent.count >= 4 else { return nil }

        // Find the most recent watering spike (sharp moisture rise > 5% in one reading)
        // and only use readings after it — avoids the rise polluting the decline slope
        for i in stride(from: recent.count - 1, through: 1, by: -1) {
            if recent[i].moisture - recent[i-1].moisture > 5 {
                recent = Array(recent[i...])
                break
            }
        }
        guard recent.count >= 4 else { return nil }

        // Use linear regression on last 24h to find moisture decline rate (% per second)
        let n = Double(recent.count)
        let xs = recent.map { $0.recordedAt.timeIntervalSinceReferenceDate }
        let ys = recent.map { $0.moisture }
        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0.0) { $0 + ($1.0 - xMean) * ($1.1 - yMean) }
        let den = xs.reduce(0.0) { $0 + ($1 - xMean) * ($1 - xMean) }
        guard den > 0 else { return nil }
        let slope = num / den  // % per second

        // Only predict if trending downward
        guard slope < -0.000001 else { return nil }

        // Current moisture (latest reading)
        guard let latest = recent.last else { return nil }
        let current = latest.moisture
        guard current > dryThreshold else { return nil } // already dry

        // Time until it hits dryThreshold at current rate
        let secondsUntilDry = (current - dryThreshold) / (-slope)
        guard secondsUntilDry > 0, secondsUntilDry < 7 * 86400 else { return nil } // max 7 days out

        return Date().addingTimeInterval(secondsUntilDry)
    }

    // MARK: - Moisture Color

    static func moistureColor(for moisture: Double) -> String {
        if moisture >= 40 { return "green" }
        if moisture >= 25 { return "yellow" }
        return "red"
    }
}
