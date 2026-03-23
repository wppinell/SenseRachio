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

    func load(modelContext: ModelContext) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

        do {
            async let sensorsTask: [SenseCraftDevice] = SenseCraftAPI.shared.listDevices()
            async let zonesTask: [RachioDevice] = RachioAPI.shared.getDevices()

            var readings: [SensorReading] = []

            // Attempt to fetch sensor readings (may fail if no creds)
            if KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) != nil {
                let devices = try await sensorsTask
                readings = await fetchReadings(for: devices)
            }

            var fetchedZones: [RachioDevice] = []
            if KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil {
                fetchedZones = (try? await zonesTask) ?? []
            }

            await MainActor.run {
                self.sensorReadings = readings
                self.zones = fetchedZones
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func fetchReadings(for devices: [SenseCraftDevice]) async -> [SensorReading] {
        var results: [SensorReading] = []
        await withTaskGroup(of: SensorReading?.self) { group in
            for device in devices {
                group.addTask {
                    do {
                        let r = try await SenseCraftAPI.shared.fetchReading(eui: device.deviceEui)
                        return SensorReading(
                            eui: device.deviceEui,
                            moisture: r.moisture ?? 0,
                            tempC: r.tempC ?? 0,
                            recordedAt: Date()
                        )
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let r = result { results.append(r) }
            }
        }
        return results
    }
}
