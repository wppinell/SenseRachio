import Foundation
import SwiftData
import Observation

@Observable
final class ZonesViewModel {
    var devices: [RachioDevice] = []
    var activeZoneId: String? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Load Zones

    func loadZones(modelContext: ModelContext) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

        do {
            let fetchedDevices = try await RachioAPI.shared.getDevices()

            // Upsert ZoneConfigs into SwiftData
            let descriptor = FetchDescriptor<ZoneConfig>()
            let existingZones = (try? modelContext.fetch(descriptor)) ?? []
            let existingById = Dictionary(uniqueKeysWithValues: existingZones.map { ($0.id, $0) })

            for device in fetchedDevices {
                for zone in device.zones {
                    if let existing = existingById[zone.id] {
                        existing.name = zone.name
                        existing.deviceId = device.id
                    } else {
                        let newZone = ZoneConfig(id: zone.id, name: zone.name, deviceId: device.id)
                        modelContext.insert(newZone)
                    }
                }
            }
            try? modelContext.save()

            await MainActor.run {
                self.devices = fetchedDevices
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Start Zone

    func startZone(id: String, duration: Int, modelContext: ModelContext) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

        do {
            try await RachioAPI.shared.startZone(id: id, duration: duration)

            // Update lastRunAt in SwiftData
            let descriptor = FetchDescriptor<ZoneConfig>(predicate: #Predicate { $0.id == id })
            if let zoneConfig = try? modelContext.fetch(descriptor).first {
                zoneConfig.lastRunAt = Date()
                try? modelContext.save()
            }

            await MainActor.run {
                self.activeZoneId = id
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Stop Zone

    func stopZone(id: String) async {
        await MainActor.run { isLoading = true; errorMessage = nil }

        do {
            try await RachioAPI.shared.stopZone(id: id)

            await MainActor.run {
                if self.activeZoneId == id {
                    self.activeZoneId = nil
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
