import Foundation
import BackgroundTasks
import SwiftData
import os

// MARK: - Background Model Actor

/// ModelActor for thread-safe SwiftData access in background tasks.
@ModelActor
actor BackgroundModelActor {
    func fetchSensorConfigs() throws -> [(eui: String, name: String, linkedZoneId: String?, isHidden: Bool)] {
        let descriptor = FetchDescriptor<SensorConfig>()
        let configs = try modelContext.fetch(descriptor)
        return configs.map { ($0.eui, $0.displayName, $0.linkedZoneId, $0.isHiddenFromGraphs) }
    }
    
    func fetchZoneName(zoneId: String) -> String? {
        let predicate = #Predicate<ZoneConfig> { $0.id == zoneId }
        let descriptor = FetchDescriptor<ZoneConfig>(predicate: predicate)
        return (try? modelContext.fetch(descriptor))?.first?.name
    }
    
    func insertReading(eui: String, moisture: Double, tempC: Double) {
        let reading = SensorReading(eui: eui, moisture: moisture, tempC: tempC, recordedAt: Date())
        modelContext.insert(reading)
    }
    
    func save() throws {
        try modelContext.save()
    }
}

// MARK: - BackgroundRefreshManager

final class BackgroundRefreshManager: Sendable {
    static let shared = BackgroundRefreshManager()
    
    private static let logger = Logger(subsystem: "com.rachiosense", category: "BackgroundRefresh")

    private let taskIdentifier = "com.rachiosense.app.refresh"
    private let refreshInterval: TimeInterval = 10 * 60 // 10 minutes

    private init() {}

    // MARK: - Register

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: refreshTask)
        }
    }

    // MARK: - Schedule

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.debug("Scheduled next background refresh")
        } catch {
            Self.logger.error("Failed to schedule task: \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Refresh

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh immediately
        scheduleAppRefresh()

        let refreshTask = Task {
            await performRefresh()
        }

        task.expirationHandler = {
            refreshTask.cancel()
            Self.logger.warning("Background task expired")
        }

        Task {
            await refreshTask.value
            task.setTaskCompleted(success: !refreshTask.isCancelled)
            Self.logger.info("Background task completed")
        }
    }

    // MARK: - Perform Refresh

    func performRefresh() async {
        guard KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) != nil else {
            Self.logger.debug("No SenseCraft credentials, skipping refresh")
            return
        }
        
        // Get global threshold from UserDefaults
        let dryThreshold = UserDefaults.standard.double(forKey: AppStorageKey.dryThreshold)
        let effectiveThreshold = dryThreshold > 0 ? dryThreshold : 25.0  // Default 25%

        do {
            // Create ModelActor for thread-safe SwiftData access
            let container = try ModelContainer(
                for: SensorConfig.self, ZoneConfig.self, SensorReading.self
            )
            let actor = BackgroundModelActor(modelContainer: container)
            
            // Fetch sensor configs
            let sensorConfigs = try await actor.fetchSensorConfigs()
            
            // Fetch readings concurrently
            struct FetchedReading: Sendable {
                let eui: String
                let moisture: Double
                let tempC: Double
                let configName: String
                let linkedZoneId: String?
            }
            
            let fetchedReadings: [FetchedReading] = await withTaskGroup(of: FetchedReading?.self) { group in
                for config in sensorConfigs {
                    if config.isHidden { continue }
                    
                    let eui = config.eui
                    let name = config.name
                    let zoneId = config.linkedZoneId
                    
                    group.addTask {
                        do {
                            let reading = try await SenseCraftAPI.shared.fetchReading(eui: eui)
                            guard let moisture = reading.moisture else { return nil }
                            return FetchedReading(
                                eui: eui,
                                moisture: moisture,
                                tempC: reading.tempC ?? 0,
                                configName: name,
                                linkedZoneId: zoneId
                            )
                        } catch {
                            Self.logger.error("Error fetching reading for \(eui): \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
                var results: [FetchedReading] = []
                for await result in group {
                    if let r = result { results.append(r) }
                }
                return results
            }
            
            Self.logger.info("Fetched \(fetchedReadings.count) readings in background")
            
            // Process results using ModelActor
            for data in fetchedReadings {
                await actor.insertReading(eui: data.eui, moisture: data.moisture, tempC: data.tempC)
                
                // Check against global threshold and send notification
                if data.moisture < effectiveThreshold {
                    var zoneName: String? = nil
                    if let zoneId = data.linkedZoneId {
                        zoneName = await actor.fetchZoneName(zoneId: zoneId)
                    }
                    
                    NotificationService.shared.scheduleNotification(
                        sensorName: data.configName,
                        zoneName: zoneName,
                        moisture: data.moisture
                    )
                }
            }

            try await actor.save()
            Self.logger.info("Background refresh saved successfully")
        } catch {
            Self.logger.error("Background refresh failed: \(error.localizedDescription)")
        }
    }
}
