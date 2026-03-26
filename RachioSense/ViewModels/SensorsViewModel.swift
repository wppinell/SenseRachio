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
                    updatedConfigs.append(existing)
                } else {
                    let newConfig = SensorConfig(
                        id: device.deviceEui,
                        name: device.deviceName,
                        eui: device.deviceEui
                    )
                    modelContext.insert(newConfig)
                    updatedConfigs.append(newConfig)
                }
            }

            try? modelContext.save()

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
                    // Skip disabled sensors
                    if disabledEuis.contains(device.deviceEui) {
                        continue
                    }
                    group.addTask {
                        do {
                            let r = try await SenseCraftAPI.shared.fetchReading(eui: device.deviceEui)
                            return ReadingData(
                                eui: device.deviceEui,
                                moisture: r.moisture ?? 0,
                                tempC: r.tempC ?? 0
                            )
                        } catch {
                            return nil
                        }
                    }
                }
                var results: [ReadingData] = []
                for await data in group {
                    if let data = data {
                        results.append(data)
                    }
                }
                return results
            }
            
            // Create moisture lookup from plain data (for sorting)
            let moistureLookup = Dictionary(uniqueKeysWithValues: fetchedReadings.map { ($0.eui, $0.moisture) })
            
            // Sort sensors by moisture ascending (driest first)
            let sortedConfigs = updatedConfigs.sorted { a, b in
                let moistureA = moistureLookup[a.eui] ?? Double.infinity
                let moistureB = moistureLookup[b.eui] ?? Double.infinity
                return moistureA < moistureB
            }
            
            // Create SwiftData models on main context
            var newReadings: [String: SensorReading] = [:]
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
