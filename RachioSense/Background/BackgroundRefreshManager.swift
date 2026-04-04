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

    // MARK: - Predictive Dry Date

    /// Returns hours until the sensor reaches `threshold`, using exponential decay fit
    /// over the last 72 hours of readings (same algorithm as SensorsViewModel).
    /// Returns nil if there isn't enough data, the sensor is already below threshold,
    /// or the trend is flat / rising.
    func predictedHoursUntil(threshold: Double, eui: String) -> Double? {
        let cutoff = Date().addingTimeInterval(-72 * 3600)
        let predicate = #Predicate<SensorReading> { $0.eui == eui && $0.recordedAt > cutoff }
        let descriptor = FetchDescriptor<SensorReading>(
            predicate: predicate,
            sortBy: [SortDescriptor(\SensorReading.recordedAt)]
        )
        var recent = (try? modelContext.fetch(descriptor)) ?? []
        guard recent.count >= 4 else { return nil }

        // Strip readings before the most recent watering spike (>5% rise)
        for i in stride(from: recent.count - 1, through: 1, by: -1) {
            if recent[i].moisture - recent[i-1].moisture > 5 {
                recent = Array(recent[i...])
                break
            }
        }
        guard recent.count >= 4, let latest = recent.last else { return nil }
        guard latest.moisture > threshold else { return nil } // already below

        // Weighted linear regression on ln(moisture) vs time → exponential decay fit
        let t0  = recent.first!.recordedAt.timeIntervalSinceReferenceDate
        let now = Date().timeIntervalSinceReferenceDate

        var wSum = 0.0, wxSum = 0.0, wySum = 0.0, wxxSum = 0.0, wxySum = 0.0
        for reading in recent {
            guard reading.moisture > 0 else { continue }
            let t   = reading.recordedAt.timeIntervalSinceReferenceDate - t0
            let y   = log(reading.moisture)
            let age = now - reading.recordedAt.timeIntervalSinceReferenceDate
            let w   = exp(-age / 14400) // half-weight every 4 h
            wSum += w; wxSum += w * t; wySum += w * y
            wxxSum += w * t * t; wxySum += w * t * y
        }

        let denom = wSum * wxxSum - wxSum * wxSum
        guard abs(denom) > 1e-10 else { return nil }
        let slope     = (wSum * wxySum - wxSum * wySum) / denom
        guard slope < 0 else { return nil } // flat or rising — no dry date
        let intercept = (wySum - slope * wxSum) / wSum

        let tNow    = now - t0
        let tTarget = (log(threshold) - intercept) / slope
        let seconds = tTarget - tNow
        guard seconds > 0 else { return nil }

        return seconds / 3600
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

        // Read thresholds from UserDefaults (with sensible defaults)
        let dryThreshold      = UserDefaults.standard.double(forKey: AppStorageKey.dryThreshold)
        let criticalThreshold = UserDefaults.standard.double(forKey: AppStorageKey.autoWaterThreshold)
        let effectiveDry      = dryThreshold > 0      ? dryThreshold      : 25.0
        let effectiveCritical = criticalThreshold > 0 ? criticalThreshold : 20.0

        // Predictive alert window (default 6 h)
        let windowHours = UserDefaults.standard.integer(forKey: AppStorageKey.predictiveAlertWindowHours)
        let alertWindow = Double(windowHours > 0 ? windowHours : 6)

        do {
            let container = try ModelContainer(
                for: SensorConfig.self, ZoneConfig.self, SensorReading.self
            )
            let actor = BackgroundModelActor(modelContainer: container)

            let sensorConfigs = try await actor.fetchSensorConfigs()

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
                    let eui    = config.eui
                    let name   = config.name
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

            // Save new readings first so the prediction math sees the latest point
            for data in fetchedReadings {
                await actor.insertReading(eui: data.eui, moisture: data.moisture, tempC: data.tempC)
            }
            try await actor.save()

            // Evaluate notifications after saving
            for data in fetchedReadings {
                let eui  = data.eui
                let name = data.configName

                // --- Predictive alerts (sensor is still above threshold but trending down) ---
                // Critical takes priority over dry; only fire one predictive alert per sensor.
                if let hrs = await actor.predictedHoursUntil(threshold: effectiveCritical, eui: eui),
                   hrs <= alertWindow {
                    Self.logger.info("Predictive critical alert for \(name): \(hrs, format: .fixed(precision: 1))h")
                    NotificationService.shared.schedulePredictiveAlert(
                        eui: eui, sensorName: name, hoursRemaining: hrs, isCritical: true
                    )
                } else if let hrs = await actor.predictedHoursUntil(threshold: effectiveDry, eui: eui),
                          hrs <= alertWindow {
                    Self.logger.info("Predictive dry alert for \(name): \(hrs, format: .fixed(precision: 1))h")
                    NotificationService.shared.schedulePredictiveAlert(
                        eui: eui, sensorName: name, hoursRemaining: hrs, isCritical: false
                    )
                }

                // --- Threshold alerts (sensor has already crossed a threshold) ---
                let isCritical = data.moisture < effectiveCritical
                let isLow      = data.moisture < effectiveDry
                if isCritical || isLow {
                    var zoneName: String? = nil
                    if let zoneId = data.linkedZoneId {
                        zoneName = await actor.fetchZoneName(zoneId: zoneId)
                    }
                    NotificationService.shared.scheduleThresholdAlert(
                        eui: eui,
                        sensorName: name,
                        zoneName: zoneName,
                        moisture: data.moisture,
                        isCritical: isCritical
                    )
                }
            }

            Self.logger.info("Background refresh completed successfully")
        } catch {
            Self.logger.error("Background refresh failed: \(error.localizedDescription)")
        }
    }
}
