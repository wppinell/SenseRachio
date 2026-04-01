import Foundation
import SwiftData
import Observation
import os

private let logger = Logger(subsystem: "com.rachiosense", category: "GraphsViewModel")

@Observable
final class GraphsViewModel {
    var sensors: [SensorConfig] = []
    var readingsByEUI: [String: [SensorReading]] = [:]
    var zoneGroups: [ZoneGroup] = []
    var zoneConfigs: [ZoneConfig] = []
    var wateringEvents: [RachioWateringEvent] = []
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
    func load(modelContext: ModelContext, forceRefresh: Bool = false) async {
        // Skip if already loaded with data
        if !forceRefresh && !sensors.isEmpty && !zoneConfigs.isEmpty { return }

        isLoading = true
        errorMessage = nil

        sensors = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []

        let groupDescriptor = FetchDescriptor<ZoneGroup>(sortBy: [SortDescriptor(\.sortOrder)])
        zoneGroups = (try? modelContext.fetch(groupDescriptor)) ?? []

        zoneConfigs = (try? modelContext.fetch(FetchDescriptor<ZoneConfig>())) ?? []

        // If no ZoneConfigs stored yet (Zones tab not visited), try to load from Rachio
        if zoneConfigs.isEmpty, KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil {
            if let devices = try? await RachioAPI.shared.getDevices() {
                let existingIds = Set(zoneConfigs.map { $0.id })
                for device in devices {
                    for zone in device.zones where zone.enabled && !existingIds.contains(zone.id) {
                        modelContext.insert(ZoneConfig(id: zone.id, name: zone.name, deviceId: device.id))
                    }
                }
                _ = try? modelContext.save()
                zoneConfigs = (try? modelContext.fetch(FetchDescriptor<ZoneConfig>())) ?? []
            }
        }

        // Show whatever is already in SwiftData immediately
        reloadReadings(modelContext: modelContext)
        isLoading = false


        // Then fetch fresh data in background — update graphs when done
        isFetchingData = true

        // Detached so tab switches don't cancel the fetch mid-flight
        let fetchTask = Task.detached(priority: .background) {
            await GraphDataPrefetcher.shared.fetchIfNeeded(modelContext: modelContext)
        }
        await fetchTask.value

        if let devices = try? await RachioAPI.shared.getDevices(),
           let deviceId = devices.first?.id {
            wateringEvents = (try? await RachioAPI.shared.getWateringEvents(deviceId: deviceId)) ?? []
        }
        reloadReadings(modelContext: modelContext)
        lastFetchedAt = Date()
        isFetchingData = false
    }
    
    /// Force refresh - fetches last 24h of fresh data (lightweight)
    @MainActor
    func forceRefresh(modelContext: ModelContext) async {
        guard !isFetchingData else { return }
        // Cooldown: ignore if refreshed less than 30s ago
        if let last = lastFetchedAt, Date().timeIntervalSince(last) < 30 { return }
        isLoading = true
        isFetchingData = true
        await GraphDataPrefetcher.shared.fetchRecent(modelContext: modelContext)
        if let devices = try? await RachioAPI.shared.getDevices(),
           let deviceId = devices.first?.id {
            wateringEvents = (try? await RachioAPI.shared.getWateringEvents(deviceId: deviceId, forceRefresh: true)) ?? []
        }
        reloadReadings(modelContext: modelContext)
        lastFetchedAt = Date()
        isFetchingData = false
        isLoading = false
    }
    
    /// Reload readings from SwiftData into memory
    @MainActor
    private func reloadReadings(modelContext: ModelContext) {
        let allReadings = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var grouped: [String: [SensorReading]] = [:]
        for r in allReadings { grouped[r.eui, default: []].append(r) }
        readingsByEUI = grouped
        let summary = grouped.map { "\($0.key.suffix(4)):\($0.value.count)" }.joined(separator: ", ")
        logger.debug(" reloadReadings: \(allReadings.count) total readings across \(grouped.keys.count) EUIs — [\(summary)]")
        
        // Also log what sensors expect to show
        let visibleEUIs = sensors.filter { !$0.isHiddenFromGraphs }.map { $0.eui }
        logger.debug(" Visible sensor EUIs: \(visibleEUIs.map { String($0.suffix(4)) }.joined(separator: ", "))")
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
        case "4d": return Date().addingTimeInterval(-4 * 86400)
        case "5d": return Date().addingTimeInterval(-5 * 86400)
        case "1w": return Date().addingTimeInterval(-7 * 86400)
        default:   return Date().addingTimeInterval(-86400)
        }
    }
}
