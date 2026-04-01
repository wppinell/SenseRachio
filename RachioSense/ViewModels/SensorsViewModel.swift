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
    func predictedCriticalDate(for eui: String, autoWaterThreshold: Double, modelContext: ModelContext) -> Date? {
        return predictedDate(for: eui, threshold: autoWaterThreshold, modelContext: modelContext)
    }

    func predictedDryDate(for eui: String, dryThreshold: Double, modelContext: ModelContext) -> Date? {
        return predictedDate(for: eui, threshold: dryThreshold, modelContext: modelContext)
    }

    private func predictedDate(for eui: String, threshold: Double, modelContext: ModelContext) -> Date? {
        // Use 72h window for slow-drying sensors like Ficus
        let cutoff = Date().addingTimeInterval(-72 * 3600)
        let descriptor = FetchDescriptor<SensorReading>(
            predicate: #Predicate { $0.eui == eui && $0.recordedAt > cutoff },
            sortBy: [SortDescriptor(\SensorReading.recordedAt)]
        )
        var recent = (try? modelContext.fetch(descriptor)) ?? []
        guard recent.count >= 4 else { return nil }

        // Strip readings before the most recent watering spike (>5% rise)
        for i in stride(from: recent.count - 1, through: 1, by: -1) {
            if recent[i].moisture - recent[i-1].moisture > 5 {
                recent = Array(recent[i...])
                break
            }
        }
        guard recent.count >= 4 else { return nil }

        guard let latest = recent.last else { return nil }
        let current = latest.moisture
        guard current > threshold else { return nil }

        // Exponential decay fit: moisture(t) = A * exp(-t / τ)
        // Linearize: ln(moisture) = ln(A) - t/τ → fit ln(y) vs t with weighted linear regression
        // Weight recent readings more heavily (exponential weights)
        let t0 = recent.first!.recordedAt.timeIntervalSinceReferenceDate
        let now = Date().timeIntervalSinceReferenceDate

        var wSum = 0.0, wxSum = 0.0, wySum = 0.0, wxxSum = 0.0, wxySum = 0.0
        for reading in recent {
            guard reading.moisture > 0 else { continue }
            let t = reading.recordedAt.timeIntervalSinceReferenceDate - t0
            let y = log(reading.moisture)
            // Weight: exponential decay so most recent readings matter most
            let age = now - reading.recordedAt.timeIntervalSinceReferenceDate
            let w = exp(-age / 14400) // half-weight every 4 hours
            wSum   += w
            wxSum  += w * t
            wySum  += w * y
            wxxSum += w * t * t
            wxySum += w * t * y
        }
        guard wSum > 0 else { return nil }

        let denom = wSum * wxxSum - wxSum * wxSum
        guard abs(denom) > 1e-10 else { return nil }

        // slope = -1/τ (must be negative for drying)
        let slope = (wSum * wxySum - wxSum * wySum) / denom
        guard slope < -1e-10 else { return nil } // not trending down

        let intercept = (wySum - slope * wxSum) / wSum
        // moisture(t) = exp(intercept) * exp(slope * t)
        // Solve for t when moisture = threshold:
        // threshold = exp(intercept + slope * t)
        // t = (ln(threshold) - intercept) / slope
        let tHit = (log(threshold) - intercept) / slope
        let tNow = now - t0
        let secondsFromNow = tHit - tNow

        guard secondsFromNow > 0, secondsFromNow < 7 * 86400 else { return nil }
        return Date().addingTimeInterval(secondsFromNow)
    }

    // MARK: - Moisture Color

    static func moistureColor(for moisture: Double) -> String {
        if moisture >= 40 { return "green" }
        if moisture >= 25 { return "yellow" }
        return "red"
    }
}
