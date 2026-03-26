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

    var senseCraftConnected: Bool = false
    var rachioConnected: Bool = false
    var rachioRateLimitMinutes: Int? = nil
    var rachioApiRemaining: Int? = nil
    var rachioApiTotal: Int? = nil
    var lastSyncDate: Date? = nil
    var forecast: WeatherAPI.Forecast? = nil

    @MainActor
    func load(modelContext: ModelContext) async {
        isLoading = true
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

        do {
            // Fetch sensors if credentials exist
            if KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) != nil {
                let devices = try await SenseCraftAPI.shared.listDevices()
                
                // Update expiry dates in SwiftData
                let existingConfigs = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []
                for device in devices {
                    if let config = existingConfigs.first(where: { $0.eui == device.deviceEui }) {
                        config.subscriptionExpiryDate = device.expiryDate
                    }
                }
                _ = try? modelContext.save()
                
                let readingData = await fetchReadingData(for: devices)
                
                if !readingData.isEmpty {
                    // Merge: fresh overrides stored, stored fills gaps
                    var merged = storedLatest
                    for data in readingData {
                        merged[data.eui] = SensorReading(eui: data.eui, moisture: data.moisture, tempC: data.tempC, recordedAt: Date())
                    }
                    self.sensorReadings = Array(merged.values)
                    self.lastSyncDate = Date()
                }
                self.senseCraftConnected = true
            } else {
                self.sensorReadings = []
                self.senseCraftConnected = false
            }

            // Fetch zones if credentials exist
            if KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil {
                do {
                    self.zones = try await RachioAPI.shared.getDevices()
                    self.rachioConnected = true
                    self.rachioRateLimitMinutes = nil
                    self.rachioApiRemaining = RachioAPI.shared.rateLimitRemaining
                    self.rachioApiTotal = RachioAPI.shared.rateLimitTotal
                } catch {
                    print("[Dashboard] Rachio fetch failed: \(error.localizedDescription)")
                    self.zones = []
                    self.rachioConnected = false
                    self.rachioRateLimitMinutes = RachioAPI.shared.rateLimitResetsInMinutes
                    self.rachioApiRemaining = RachioAPI.shared.rateLimitRemaining
                    self.rachioApiTotal = RachioAPI.shared.rateLimitTotal
                }
            } else {
                self.zones = []
                self.rachioConnected = false
            }

            // Fetch weather in parallel (don't block sensors/zones loading)
            if forecast == nil {
                Task {
                    forecast = try? await WeatherAPI.shared.fetchForecast(latitude: 33.4484, longitude: -112.0740)
                }
            }

            isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.senseCraftConnected = false
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
                        guard let moisture = r.moisture else { return nil }
                        return ReadingData(eui: device.deviceEui, moisture: moisture, tempC: r.tempC ?? 0)
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
