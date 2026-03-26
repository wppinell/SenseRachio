import Foundation
import SwiftData
import Observation

@Observable
final class GraphsViewModel {
    var sensors: [SensorConfig] = []
    var readingsByEUI: [String: [SensorReading]] = [:]
    var zoneGroups: [ZoneGroup] = []
    var zoneConfigs: [ZoneConfig] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Computed

    var visibleSensors: [SensorConfig] {
        sensors.filter { !$0.isHiddenFromGraphs }
    }

    /// Zones that have at least one visible sensor linked to them, sorted by name.
    var zonesWithLinkedSensors: [ZoneConfig] {
        zoneConfigs
            .filter { zone in visibleSensors.contains(where: { $0.linkedZoneId == zone.id }) }
            .sorted { $0.name < $1.name }
    }

    /// Visible sensors with no linkedZoneId.
    var unlinkedSensors: [SensorConfig] {
        visibleSensors.filter { $0.linkedZoneId == nil }
    }

    /// Returns visible sensors linked to a specific zone.
    func sensors(linkedTo zoneId: String) -> [SensorConfig] {
        visibleSensors.filter { $0.linkedZoneId == zoneId }
    }

    /// Returns visible sensors whose linkedZoneId is in the group's assignedZoneIds.
    func sensors(forGroup group: ZoneGroup) -> [SensorConfig] {
        visibleSensors.filter { sensor in
            guard let zoneId = sensor.linkedZoneId else { return false }
            return group.assignedZoneIds.contains(zoneId)
        }
    }

    func readings(for eui: String, period: String) -> [(Date, Double)] {
        let cutoff = cutoffDate(for: period)
        return (readingsByEUI[eui] ?? [])
            .filter { $0.recordedAt >= cutoff }
            .map { ($0.recordedAt, $0.moisture) }
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - Data Loading

    @MainActor
    func load(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil

        sensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []

        let groupDescriptor = FetchDescriptor<ZoneGroup>(sortBy: [SortDescriptor(\.sortOrder)])
        zoneGroups = (try? modelContext.fetch(groupDescriptor)) ?? []

        zoneConfigs = (try? modelContext.fetch(FetchDescriptor<ZoneConfig>())) ?? []

        let allReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var grouped: [String: [SensorReading]] = [:]
        for r in allReadings { grouped[r.eui, default: []].append(r) }
        readingsByEUI = grouped

        isLoading = false
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
