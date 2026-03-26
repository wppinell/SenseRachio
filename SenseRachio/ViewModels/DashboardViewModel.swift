import Foundation
import SwiftData
import Observation

@Observable
final class DashboardViewModel {
    var sensorReadings: [SensorReading] = []
    var zones: [RachioDevice] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Computed

    var driestSensor: (config: SensorConfig?, reading: SensorReading?)? {
        guard let driest = sensorReadings.min(by: { $0.moisture < $1.moisture }) else {
            return nil
        }
        return (config: nil, reading: driest)
    }

    var totalSensors: Int {
        sensorReadings.count
    }

    var enabledZonesCount: Int {
        zones.flatMap(\.zones).filter(\.enabled).count
    }

    // MARK: - Load

    @MainActor
    func load(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch sensors if credentials exist
            if KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) != nil {
                let devices = try await SenseCraftAPI.shared.listDevices()
                let readingData = await fetchReadingData(for: devices)
                // Create SwiftData models on main actor
                self.sensorReadings = readingData.map { data in
                    SensorReading(
                        eui: data.eui,
                        moisture: data.moisture,
                        tempC: data.tempC,
                        recordedAt: Date()
                    )
                }
            } else {
                self.sensorReadings = []
            }

            // Fetch zones if credentials exist
            if KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil {
                self.zones = (try? await RachioAPI.shared.getDevices()) ?? []
            } else {
                self.zones = []
            }

            isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private struct ReadingData: Sendable {
        let eui: String
        let moisture: Double
        let tempC: Double
    }
    
    private func fetchReadingData(for devices: [SenseCraftDevice]) async -> [ReadingData] {
        var fetchedData: [ReadingData] = []
        await withTaskGroup(of: ReadingData?.self) { group in
            for device in devices {
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
            for await data in group {
                if let d = data { fetchedData.append(d) }
            }
        }
        return fetchedData
    }
}
