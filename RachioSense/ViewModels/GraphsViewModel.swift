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
    var isFetchingData: Bool = false  // true while network fetch in-progress
    var errorMessage: String? = nil
    private(set) var lastFetchedAt: Date? = nil

    /// True if no fetch has happened yet, or last fetch was > 10 minutes ago
    var isDataStale: Bool {
        guard let last = lastFetchedAt else { return true }
        return Date().timeIntervalSince(last) > 600
    }

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
    
    /// Zones that have linked sensors but are NOT in any group.
    var zonesNotInAnyGroup: [ZoneConfig] {
        let allGroupedZoneIds = Set(zoneGroups.flatMap { $0.assignedZoneIds })
        return zonesWithLinkedSensors.filter { !allGroupedZoneIds.contains($0.id) }
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

        // Wait for prefetcher to finish before reading — ensures graphs show full history
        isFetchingData = true
        await GraphDataPrefetcher.shared.fetchIfNeeded(modelContext: modelContext)
        isFetchingData = false

        reloadReadings(modelContext: modelContext)
        lastFetchedAt = Date()
        isLoading = false
    }
    
    /// Force refresh - clears local data, fetches fresh, then reloads
    @MainActor
    func forceRefresh(modelContext: ModelContext) async {
        isLoading = true
        // Invalidate displayed readings immediately so graphs show waiting state
        readingsByEUI = [:]
        isFetchingData = true
        await GraphDataPrefetcher.shared.forceFull(modelContext: modelContext)
        isFetchingData = false
        reloadReadings(modelContext: modelContext)
        lastFetchedAt = Date()
        isLoading = false
    }
    
    /// Reload readings from SwiftData into memory
    @MainActor
    private func reloadReadings(modelContext: ModelContext) {
        let allReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var grouped: [String: [SensorReading]] = [:]
        for r in allReadings { grouped[r.eui, default: []].append(r) }
        readingsByEUI = grouped
    }
    

    // MARK: - Lightweight Refresh (fetch latest only)
    
    @MainActor
    func refreshLatest(modelContext: ModelContext) async {
        let sensorsToRefresh = visibleSensors
        let now = Date()

        // Fetch all sensors in parallel
        let results = await withTaskGroup(of: (String, SenseCraftReading?).self) { group in
            for sensor in sensorsToRefresh {
                group.addTask {
                    do {
                        let reading = try await SenseCraftAPI.shared.fetchReading(eui: sensor.eui)
                        return (sensor.eui, reading)
                    } catch {
                        print("Refresh failed for \(sensor.eui): \(error)")
                        return (sensor.eui, nil)
                    }
                }
            }
            var collected: [(String, SenseCraftReading?)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        // Insert on main actor
        for (eui, reading) in results {
            guard let moisture = reading?.moisture else { continue }
            let newReading = SensorReading(
                eui: eui,
                moisture: moisture,
                tempC: reading?.tempC ?? 0,
                recordedAt: now
            )
            modelContext.insert(newReading)
        }
        _ = try? modelContext.save()

        // Reload readings into memory
        let allReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var grouped: [String: [SensorReading]] = [:]
        for r in allReadings { grouped[r.eui, default: []].append(r) }
        readingsByEUI = grouped
        lastFetchedAt = Date()
    }

    // MARK: - Private

    private func cutoffDate(for period: String) -> Date {
        switch period {
        case "1d": return Date().addingTimeInterval(-1 * 86400)
        case "2d": return Date().addingTimeInterval(-2 * 86400)
        case "3d": return Date().addingTimeInterval(-3 * 86400)
        case "4d": return Date().addingTimeInterval(-4 * 86400)
        case "5d": return Date().addingTimeInterval(-5 * 86400)
        case "1w": return Date().addingTimeInterval(-7 * 86400)
        case "2w": return Date().addingTimeInterval(-14 * 86400)
        default:   return Date().addingTimeInterval(-86400)
        }
    }
}
