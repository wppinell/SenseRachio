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

            // Fetch readings for each sensor
            await withTaskGroup(of: Void.self) { group in
                for config in sensorConfigs {
                    group.addTask {
                        do {
                            let reading = try await SenseCraftAPI.shared.fetchReading(eui: config.eui)
                            let moisture = reading.moisture ?? 0
                            let tempC = reading.tempC ?? 0

                            let newReading = SensorReading(
                                eui: config.eui,
                                moisture: moisture,
                                tempC: tempC,
                                recordedAt: Date()
                            )
                            await MainActor.run {
                                context.insert(newReading)
                            }

                            // Check threshold and send notification
                            if let threshold = config.moistureThreshold,
                               moisture < threshold {
                                // Find linked zone name
                                var zoneName: String? = nil
                                if let zoneId = config.linkedZoneId {
                                    let zoneDescriptor = FetchDescriptor<ZoneConfig>(
                                        predicate: #Predicate { $0.id == zoneId }
                                    )
                                    zoneName = (try? context.fetch(zoneDescriptor))?.first?.name
                                }

                                await NotificationService.shared.scheduleNotification(
                                    sensorName: config.name,
                                    zoneName: zoneName,
                                    moisture: moisture
                                )
                            }
                        } catch {
                            print("BackgroundRefreshManager: Error fetching reading for \(config.eui): \(error)")
                        }
                    }
                }
            }

            try? context.save()
        } catch {
            print("BackgroundRefreshManager: Failed to create container: \(error)")
        }
    }
}
