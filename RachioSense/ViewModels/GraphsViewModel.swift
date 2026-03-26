import Foundation
import SwiftData
import Observation

@Observable
final class GraphsViewModel {
    var sensors: [SensorConfig] = []
    var readingsByEUI: [String: [SensorReading]] = [:]
    var latestByEUI: [String: SensorReading] = [:]
    var groups: [SensorGroup] = []
    var zoneConfigs: [ZoneConfig] = []
    var rachioDevices: [RachioDevice] = []
    var activeZoneId: String? = nil
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Computed

    var visibleSensors: [SensorConfig] {
        sensors.filter { !$0.isHiddenFromGraphs }
    }

    var isMissionControlAvailable: Bool {
        !rachioDevices.isEmpty && sensors.contains(where: { $0.linkedZoneId != nil })
    }

    var groupsWithSensors: [SensorGroup] {
        groups.filter { group in
            visibleSensors.contains(where: { $0.groupId == group.id })
        }
    }

    var ungroupedVisibleSensors: [SensorConfig] {
        visibleSensors.filter { $0.groupId == nil }
    }

    func visibleSensors(inGroup groupId: String) -> [SensorConfig] {
        visibleSensors.filter { $0.groupId == groupId }
    }

    func readings(for eui: String, period: String) -> [(Date, Double)] {
        let cutoff = cutoffDate(for: period)
        return (readingsByEUI[eui] ?? [])
            .filter { $0.recordedAt >= cutoff }
            .map { ($0.recordedAt, $0.moisture) }
            .sorted { $0.0 < $1.0 }
    }

    func zoneName(for zoneId: String) -> String? {
        zoneConfigs.first(where: { $0.id == zoneId })?.name
    }

    func lastRunAt(for zoneId: String) -> Date? {
        zoneConfigs.first(where: { $0.id == zoneId })?.lastRunAt
    }

    func isZoneActive(_ zoneId: String) -> Bool {
        activeZoneId == zoneId
    }

    // MARK: - Mission Control Cards

    struct MissionCard: Identifiable {
        let id: String
        let title: String
        let sensors: [SensorConfig]
        let zoneId: String?
    }

    var missionCards: [MissionCard] {
        if !groupsWithSensors.isEmpty {
            return groupsWithSensors.map { group in
                let groupSensors = visibleSensors(inGroup: group.id)
                let zoneId = groupSensors.compactMap(\.linkedZoneId).first
                return MissionCard(id: group.id, title: group.name, sensors: groupSensors, zoneId: zoneId)
            }
        } else {
            // Group by linkedZoneId
            var byZone: [String: [SensorConfig]] = [:]
            for sensor in visibleSensors where sensor.linkedZoneId != nil {
                byZone[sensor.linkedZoneId!, default: []].append(sensor)
            }
            return byZone.map { zoneId, sensors in
                MissionCard(
                    id: zoneId,
                    title: zoneName(for: zoneId) ?? "Zone",
                    sensors: sensors,
                    zoneId: zoneId
                )
            }.sorted { $0.title < $1.title }
        }
    }

    // MARK: - Data Loading

    @MainActor
    func load(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil

        sensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []

        let groupDescriptor = FetchDescriptor<SensorGroup>(sortBy: [SortDescriptor(\.sortOrder)])
        groups = (try? modelContext.fetch(groupDescriptor)) ?? []

        zoneConfigs = (try? modelContext.fetch(FetchDescriptor<ZoneConfig>())) ?? []

        let allReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var grouped: [String: [SensorReading]] = [:]
        for r in allReadings {
            grouped[r.eui, default: []].append(r)
        }
        readingsByEUI = grouped
        latestByEUI = grouped.compactMapValues { $0.max(by: { $0.recordedAt < $1.recordedAt }) }

        // Load Rachio devices (non-fatal if unavailable)
        if KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil {
            do {
                rachioDevices = try await RachioAPI.shared.getDevices()
            } catch {
                rachioDevices = []
            }
        }

        isLoading = false
    }

    @MainActor
    func startZone(id: String, modelContext: ModelContext) async {
        do {
            try await RachioAPI.shared.startZone(id: id, duration: 600)
            activeZoneId = id
            let desc = FetchDescriptor<ZoneConfig>(predicate: #Predicate { $0.id == id })
            if let zoneConfig = try? modelContext.fetch(desc).first {
                zoneConfig.lastRunAt = Date()
                try? modelContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func stopZone(id: String) async {
        do {
            try await RachioAPI.shared.stopZone(id: id)
            if activeZoneId == id { activeZoneId = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func cutoffDate(for period: String) -> Date {
        switch period {
        case "6h":  return Date().addingTimeInterval(-6 * 3600)
        case "12h": return Date().addingTimeInterval(-12 * 3600)
        case "7d":  return Date().addingTimeInterval(-7 * 86400)
        default:    return Date().addingTimeInterval(-86400)
        }
    }
}
