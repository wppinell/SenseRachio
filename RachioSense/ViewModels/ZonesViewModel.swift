import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ZonesViewModel {
    var devices: [RachioDevice] = []
    var activeZoneId: String? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Load Zones

    private var lastLoadedAt: Date? = nil

    func loadZones(modelContext: ModelContext, forceRefresh: Bool = false) async {
        // Skip if recently loaded and not forced (ViewModel-level guard prevents
        // unnecessary SwiftData upsert work even when RachioAPI cache is warm)
        if !forceRefresh, let last = lastLoadedAt, Date().timeIntervalSince(last) < 300, !devices.isEmpty {
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            let fetchedDevices = try await RachioAPI.shared.getDevices(forceRefresh: forceRefresh)

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

            self.devices = fetchedDevices
            self.lastLoadedAt = Date()
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: - Start Zone

    func startZone(id: String, duration: Int, modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil

        do {
            try await RachioAPI.shared.startZone(id: id, duration: duration)

            // Update lastRunAt in SwiftData
            let descriptor = FetchDescriptor<ZoneConfig>(predicate: #Predicate { $0.id == id })
            if let zoneConfig = try? modelContext.fetch(descriptor).first {
                zoneConfig.lastRunAt = Date()
                try? modelContext.save()
            }

            self.activeZoneId = id
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: - Stop Zone

    func stopZone(id: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await RachioAPI.shared.stopZone(id: id)

            if self.activeZoneId == id {
                self.activeZoneId = nil
            }
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: - Stop All Zones

    func stopAllZones() async {
        isLoading = true
        errorMessage = nil

        let allZones = devices.flatMap(\.zones).filter(\.enabled)
        var errors: [Error] = []

        for zone in allZones {
            do {
                try await RachioAPI.shared.stopZone(id: zone.id)
            } catch {
                errors.append(error)
            }
        }

        self.activeZoneId = nil
        self.isLoading = false

        // Report first error if any zones failed to stop
        if let first = errors.first {
            self.errorMessage = errors.count == 1
                ? first.localizedDescription
                : "\(errors.count) zones failed to stop. First error: \(first.localizedDescription)"
        }
    }
}
