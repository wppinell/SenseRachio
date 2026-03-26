import Foundation
import SwiftData
import Observation

@Observable
final class SensorsViewModel {
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
            // For each EUI, find the most recent stored reading
            var storedLatest: [String: SensorReading] = [:]
            for r in allStored {
                if let existing = storedLatest[r.eui] {
                    if r.recordedAt > existing.recordedAt { storedLatest[r.eui] = r }
                } else {
                    storedLatest[r.eui] = r
                }
            }

            // Fetch latest readings concurrently (as plain data, not SwiftData models)
            struct ReadingData: Sendable {
                let eui: String
                let moisture: Double
                let tempC: Double
            }
            
            // Get disabled sensor EUIs to skip
            let disabledEuis = Set(updatedConfigs.filter { $0.isHiddenFromGraphs }.map { $0.eui })
            
            let fetchedReadings: [ReadingData] = await withTaskGroup(of: ReadingData?.self) { group in
                for device in devices {
                    if disabledEuis.contains(device.deviceEui) { continue }
                    group.addTask {
                        do {
                            let r = try await SenseCraftAPI.shared.fetchReading(eui: device.deviceEui)
                            // Only return if we got real data
                            guard let moisture = r.moisture else { return nil }
                            return ReadingData(eui: device.deviceEui, moisture: moisture, tempC: r.tempC ?? 0)
                        } catch {
                            return nil  // Failed — will fall back to stored reading
                        }
                    }
                }
                var results: [ReadingData] = []
                for await data in group {
                    if let data = data { results.append(data) }
                }
                return results
            }
            
            // Merge: use fresh reading if available, fall back to last stored reading
            var newReadings: [String: SensorReading] = [:]
            
            // First seed with stored readings as fallback
            for (eui, stored) in storedLatest {
                newReadings[eui] = stored
            }
            
            // Override with fresh readings where we got them
            for data in fetchedReadings {
                let reading = SensorReading(
                    eui: data.eui,
                    moisture: data.moisture,
                    tempC: data.tempC,
                    recordedAt: Date()
                )
                modelContext.insert(reading)
                newReadings[data.eui] = reading
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
