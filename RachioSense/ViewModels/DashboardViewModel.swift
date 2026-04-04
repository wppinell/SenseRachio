import Foundation
import SwiftData
import Observation
import os

@Observable
final class DashboardViewModel {
    private static let logger = Logger(subsystem: "com.rachiosense", category: "DashboardViewModel")
    
    var sensorReadings: [SensorReading] = []
    var zones: [RachioDevice] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Computed

    var driestSensor: SensorReading? {
        sensorReadings.min(by: { $0.moisture < $1.moisture })
    }

    var totalSensors: Int {
        sensorReadings.count
    }

    var enabledZonesCount: Int {
        zones.flatMap(\.zones).filter(\.enabled).count
    }

    // MARK: - Load

    var senseCraftConnected: Bool = false
    var rachioConnected: Bool = false
    var rachioRateLimitMinutes: Int? = nil
    var rachioApiRemaining: Int? = nil
    var rachioApiTotal: Int? = nil
    var lastSyncDate: Date? = nil
    var forecast: WeatherAPI.Forecast? = nil
    var weatherFetchedAt: Date? = nil

    @MainActor
    func load(modelContext: ModelContext) async {
        isLoading = zones.isEmpty  // only show full loading screen on first load
        errorMessage = nil

        // Always seed with stored readings first so UI never goes blank
        let allStored = (try? modelContext.fetch(FetchDescriptor<SensorReading>())) ?? []
        var storedLatest: [String: SensorReading] = [:]
        for r in allStored {
            if let existing = storedLatest[r.eui] {
                if r.recordedAt > existing.recordedAt { storedLatest[r.eui] = r }
            } else {
                storedLatest[r.eui] = r
            }
        }
        if !storedLatest.isEmpty {
            self.sensorReadings = Array(storedLatest.values)
            self.lastSyncDate = storedLatest.values.max(by: { $0.recordedAt < $1.recordedAt })?.recordedAt
        }

        // Run SenseCraft, Rachio, and weather all in parallel
        let storedLatestCopy = storedLatest // capture for sendability
        async let sensorsTask: Void = fetchSensors(storedLatest: storedLatestCopy, modelContext: modelContext)
        async let zonesTask: Void = fetchZones()
        async let weatherTask: Void = fetchWeather()
        await sensorsTask
        await zonesTask
        await weatherTask

        isLoading = false
    }

    private func fetchSensors(storedLatest: [String: SensorReading], modelContext: ModelContext) async {
        guard KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) != nil else {
            self.sensorReadings = []
            self.senseCraftConnected = false
            return
        }
        let hiddenEuis = Set((try? modelContext.fetch(FetchDescriptor<SensorConfig>()))?.filter { $0.isHiddenFromGraphs }.map { $0.eui } ?? [])
        let allCachedReadings = await LiveReadingsCache.shared.getReadings()
        let cachedReadings = allCachedReadings.filter { !hiddenEuis.contains($0.key) }
        if !cachedReadings.isEmpty {
            var merged = storedLatest
            for (eui, reading) in cachedReadings { merged[eui] = reading }
            self.sensorReadings = Array(merged.values)
            self.lastSyncDate = await LiveReadingsCache.shared.getLastFetchDate()
        }
        self.senseCraftConnected = true
    }

    private func fetchZones() async {
        guard KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil else {
            self.zones = []
            self.rachioConnected = false
            return
        }
        do {
            self.zones = try await RachioAPI.shared.getDevices()
            self.rachioConnected = true
            self.rachioRateLimitMinutes = nil
            self.rachioApiRemaining = await RachioAPI.shared.rateLimitRemaining
            self.rachioApiTotal = await RachioAPI.shared.rateLimitTotal
        } catch {
            Self.logger.error("Rachio fetch failed: \(error.localizedDescription)")
            self.zones = []
            self.rachioConnected = false
            self.rachioRateLimitMinutes = await RachioAPI.shared.rateLimitResetsInMinutes
            self.rachioApiRemaining = await RachioAPI.shared.rateLimitRemaining
            self.rachioApiTotal = await RachioAPI.shared.rateLimitTotal
        }
    }

    private func fetchWeather() async {
        // Use cached forecast if fresh (< 30 min old)
        if let lastFetch = weatherFetchedAt,
           Date().timeIntervalSince(lastFetch) < 1800,
           forecast != nil { return }

        let location = await LocationManager.shared.getLocation()
        if let result = try? await WeatherAPI.shared.fetchForecast(
            latitude: location.latitude,
            longitude: location.longitude
        ) {
            forecast = result
            weatherFetchedAt = Date()
        }
    }
}
