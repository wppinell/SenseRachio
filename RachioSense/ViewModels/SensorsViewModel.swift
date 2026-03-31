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

    // MARK: - Load Sensors

    @MainActor
    func loadSensors(modelContext: ModelContext) async {
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
            self.isLoading = false
        } catch {
            Self.logger.error("Failed to load sensors: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: - Moisture Color

    static func moistureColor(for moisture: Double) -> String {
        if moisture >= 40 { return "green" }
        if moisture >= 25 { return "yellow" }
        return "red"
    }
}
