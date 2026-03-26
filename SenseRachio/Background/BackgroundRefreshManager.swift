import Foundation
import BackgroundTasks
import SwiftData

final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()

    private let taskIdentifier = "com.senserachio.app.refresh"
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
        } catch {
            print("BackgroundRefreshManager: Failed to schedule task: \(error)")
        }
    }

    // MARK: - Handle Refresh

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh immediately
        scheduleAppRefresh()

        let taskGroup = Task {
            await performRefresh()
        }

        task.expirationHandler = {
            taskGroup.cancel()
        }

        Task {
            await taskGroup.value
            task.setTaskCompleted(success: !taskGroup.isCancelled)
        }
    }

    // MARK: - Perform Refresh

    @MainActor
    func performRefresh() async {
        guard KeychainService.shared.load(forKey: KeychainKey.senseCraftAPIKey) != nil else {
            return
        }

        do {
            // Build a model container for background use
            let container = try ModelContainer(
                for: SensorConfig.self, ZoneConfig.self, SensorReading.self
            )
            let context = ModelContext(container)

            // Fetch all sensor configs
            let descriptor = FetchDescriptor<SensorConfig>()
            let sensorConfigs = (try? context.fetch(descriptor)) ?? []

            // Fetch readings for each sensor (collect plain data first)
            struct FetchedReading: Sendable {
                let eui: String
                let moisture: Double
                let tempC: Double
                let configName: String
                let threshold: Double?
                let linkedZoneId: String?
            }
            
            let fetchedReadings: [FetchedReading] = await withTaskGroup(of: FetchedReading?.self) { group in
                for config in sensorConfigs {
                    let eui = config.eui
                    let name = config.name
                    let threshold = config.moistureThreshold
                    let zoneId = config.linkedZoneId
                    
                    group.addTask {
                        do {
                            let reading = try await SenseCraftAPI.shared.fetchReading(eui: eui)
                            return FetchedReading(
                                eui: eui,
                                moisture: reading.moisture ?? 0,
                                tempC: reading.tempC ?? 0,
                                configName: name,
                                threshold: threshold,
                                linkedZoneId: zoneId
                            )
                        } catch {
                            print("BackgroundRefreshManager: Error fetching reading for \(eui): \(error)")
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
            
            // Process results on main actor
            for data in fetchedReadings {
                let newReading = SensorReading(
                    eui: data.eui,
                    moisture: data.moisture,
                    tempC: data.tempC,
                    recordedAt: Date()
                )
                context.insert(newReading)
                
                // Check threshold and send notification
                if let threshold = data.threshold, data.moisture < threshold {
                    var zoneName: String? = nil
                    if let zoneId = data.linkedZoneId {
                        let zoneDescriptor = FetchDescriptor<ZoneConfig>(
                            predicate: #Predicate { $0.id == zoneId }
                        )
                        zoneName = (try? context.fetch(zoneDescriptor))?.first?.name
                    }
                    
                    NotificationService.shared.scheduleNotification(
                        sensorName: data.configName,
                        zoneName: zoneName,
                        moisture: data.moisture
                    )
                }
            }

            _ = try? context.save()
        } catch {
            print("BackgroundRefreshManager: Failed to create container: \(error)")
        }
    }
}
