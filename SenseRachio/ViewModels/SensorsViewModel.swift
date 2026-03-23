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

    func loadSensors(modelContext: ModelContext) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

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

            // Fetch latest readings concurrently
            var newReadings: [String: SensorReading] = [:]
            await withTaskGroup(of: (String, SensorReading?).self) { group in
                for device in devices {
                    group.addTask {
                        do {
                            let r = try await SenseCraftAPI.shared.fetchReading(eui: device.deviceEui)
                            let reading = SensorReading(
                                eui: device.deviceEui,
                                moisture: r.moisture ?? 0,
                                tempC: r.tempC ?? 0,
                                recordedAt: Date()
                            )
                            return (device.deviceEui, reading)
                        } catch {
                            return (device.deviceEui, nil)
                        }
                    }
                }
                for await (eui, reading) in group {
                    if let reading = reading {
                        newReadings[eui] = reading
                        modelContext.insert(reading)
                    }
                }
            }
            try? modelContext.save()

            // Sort sensors by moisture ascending (driest first)
            let sortedConfigs = updatedConfigs.sorted { a, b in
                let moistureA = newReadings[a.eui]?.moisture ?? Double.infinity
                let moistureB = newReadings[b.eui]?.moisture ?? Double.infinity
                return moistureA < moistureB
            }

            await MainActor.run {
                self.sensors = sortedConfigs
                self.readings = newReadings
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Moisture Color

    static func moistureColor(for moisture: Double) -> String {
        if moisture >= 40 { return "green" }
        if moisture >= 25 { return "yellow" }
        return "red"
    }
}
