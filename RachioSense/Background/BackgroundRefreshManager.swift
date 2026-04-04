import Foundation
import BackgroundTasks
import SwiftData
import os

// MARK: - Sensor Summary Data

struct DriestSensor: Sendable {
    let name: String
    let eui: String
    let moisture: Double
}

struct SensorSummaryData: Sendable {
    let healthy: Int
    let low: Int
    let critical: Int
    let totalMoisture: Double
    let totalCount: Int
    let driest: DriestSensor?
}

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

    // MARK: - Last Reading Date

    func latestReadingDate(eui: String) -> Date? {
        var descriptor = FetchDescriptor<SensorReading>(
            predicate: #Predicate { $0.eui == eui },
            sortBy: [SortDescriptor(\SensorReading.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.recordedAt
    }

    // MARK: - Sensor Summary

    func sensorSummary(dryThreshold: Double, criticalThreshold: Double) -> SensorSummaryData {
        let configs = (try? modelContext.fetch(FetchDescriptor<SensorConfig>())) ?? []
        var healthy = 0, low = 0, critical = 0
        var totalMoisture = 0.0
        var count = 0
        var driest: DriestSensor? = nil

        for config in configs where !config.isHiddenFromGraphs {
            let eui = config.eui   // capture as plain String — #Predicate can't use @Model properties directly
            var desc = FetchDescriptor<SensorReading>(
                predicate: #Predicate { $0.eui == eui },
                sortBy: [SortDescriptor(\SensorReading.recordedAt, order: .reverse)]
            )
            desc.fetchLimit = 1
            guard let reading = (try? modelContext.fetch(desc))?.first else { continue }

            let m = reading.moisture
            totalMoisture += m
            count += 1

            if m < criticalThreshold      { critical += 1 }
            else if m < dryThreshold      { low += 1 }
            else                          { healthy += 1 }

            if driest == nil || m < driest!.moisture {
                driest = DriestSensor(name: config.displayName, eui: config.eui, moisture: m)
            }
        }

        return SensorSummaryData(
            healthy: healthy, low: low, critical: critical,
            totalMoisture: totalMoisture, totalCount: count, driest: driest
        )
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

        // Read thresholds (with sensible defaults)
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

            // --- Fetch sensor readings concurrently ---
            struct FetchedReading: Sendable {
                let eui: String
                let moisture: Double
                let tempC: Double
                let configName: String
                let linkedZoneId: String?
            }

            let fetchedReadings: [FetchedReading] = await withTaskGroup(of: FetchedReading?.self) { group in
                for config in sensorConfigs where !config.isHidden {
                    let eui = config.eui; let name = config.name; let zoneId = config.linkedZoneId
                    group.addTask {
                        do {
                            let reading = try await SenseCraftAPI.shared.fetchReading(eui: eui)
                            guard let moisture = reading.moisture else { return nil }
                            return FetchedReading(eui: eui, moisture: moisture,
                                                  tempC: reading.tempC ?? 0,
                                                  configName: name, linkedZoneId: zoneId)
                        } catch {
                            Self.logger.error("Error fetching \(eui): \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
                var results: [FetchedReading] = []
                for await r in group { if let r { results.append(r) } }
                return results
            }

            Self.logger.info("Fetched \(fetchedReadings.count) readings in background")

            // Track SenseCraft connectivity for service-disconnected alerts
            let visibleSensorCount = sensorConfigs.filter { !$0.isHidden }.count
            if !fetchedReadings.isEmpty {
                UserDefaults.standard.set(Date(), forKey: "notif_sensecraft_last_success")
            } else if visibleSensorCount > 0 {
                Self.logger.warning("SenseCraft returned 0 readings for \(visibleSensorCount) visible sensors")
            }

            // Save first so prediction math and summary see the latest values
            for data in fetchedReadings {
                await actor.insertReading(eui: data.eui, moisture: data.moisture, tempC: data.tempC)
            }
            try await actor.save()

            // --- Moisture alerts (predictive + threshold) ---
            for data in fetchedReadings {
                let eui = data.eui; let name = data.configName

                if let hrs = await actor.predictedHoursUntil(threshold: effectiveCritical, eui: eui),
                   hrs <= alertWindow {
                    Self.logger.info("Predictive critical: \(name) in \(hrs, format: .fixed(precision: 1))h")
                    NotificationService.shared.schedulePredictiveAlert(
                        eui: eui, sensorName: name, hoursRemaining: hrs, isCritical: true)
                } else if let hrs = await actor.predictedHoursUntil(threshold: effectiveDry, eui: eui),
                          hrs <= alertWindow {
                    Self.logger.info("Predictive dry: \(name) in \(hrs, format: .fixed(precision: 1))h")
                    NotificationService.shared.schedulePredictiveAlert(
                        eui: eui, sensorName: name, hoursRemaining: hrs, isCritical: false)
                }

                let isCritical = data.moisture < effectiveCritical
                let isLow      = data.moisture < effectiveDry
                if isCritical || isLow {
                    var zoneName: String? = nil
                    if let zoneId = data.linkedZoneId {
                        zoneName = await actor.fetchZoneName(zoneId: zoneId)
                    }
                    NotificationService.shared.scheduleThresholdAlert(
                        eui: eui, sensorName: name, zoneName: zoneName,
                        moisture: data.moisture, isCritical: isCritical)
                }
            }

            // --- Sensor offline check ---
            let fetchedEUIs = Set(fetchedReadings.map { $0.eui })
            await checkSensorOffline(fetchedEUIs: fetchedEUIs, allConfigs: sensorConfigs, actor: actor)

            // --- Zone notifications + skip alerts (single getDevices() call shared by both) ---
            if KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil {
                if let rachioDevices = try? await RachioAPI.shared.getDevices() {
                    UserDefaults.standard.set(Date(), forKey: "notif_rachio_last_success")
                    let wantRan      = UserDefaults.standard.object(forKey: AppStorageKey.zoneStoppedEnabled) as? Bool ?? false
                    let wantUpcoming = UserDefaults.standard.object(forKey: AppStorageKey.scheduleRunEnabled)  as? Bool ?? false
                    let wantSkip     = UserDefaults.standard.object(forKey: AppStorageKey.zoneSkipEnabled)     as? Bool ?? true
                    if wantRan || wantUpcoming { await checkZoneNotifications(devices: rachioDevices) }
                    if wantSkip               { await checkZoneSkips(devices: rachioDevices) }
                }
            }

            // --- Service disconnected alerts ---
            checkServiceAlerts(visibleSensorCount: visibleSensorCount)

            // --- Daily summary & weekly report ---
            let summary = await actor.sensorSummary(dryThreshold: effectiveDry, criticalThreshold: effectiveCritical)

            if UserDefaults.standard.object(forKey: AppStorageKey.dailySummaryEnabled) as? Bool ?? false {
                checkDailySummary(summary: summary)
            }
            if UserDefaults.standard.object(forKey: AppStorageKey.weeklyReportEnabled) as? Bool ?? false {
                checkWeeklyReport(summary: summary)
            }

            Self.logger.info("Background refresh completed successfully")
        } catch {
            Self.logger.error("Background refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sensor Offline Check

    private func checkSensorOffline(
        fetchedEUIs: Set<String>,
        allConfigs: [(eui: String, name: String, linkedZoneId: String?, isHidden: Bool)],
        actor: BackgroundModelActor
    ) async {
        let offlineThresholdHours = 3.0 // ~3 background cycles
        let now = Date()

        for config in allConfigs where !config.isHidden {
            guard !fetchedEUIs.contains(config.eui) else { continue } // got a reading — not offline
            guard let lastSeen = await actor.latestReadingDate(eui: config.eui) else { continue }
            let hoursOffline = now.timeIntervalSince(lastSeen) / 3600
            guard hoursOffline >= offlineThresholdHours else { continue }

            Self.logger.info("Offline alert: \(config.name) last seen \(hoursOffline, format: .fixed(precision: 1))h ago")
            NotificationService.shared.scheduleSensorOfflineAlert(
                eui: config.eui, sensorName: config.name, hoursOffline: hoursOffline)
        }
    }

    // MARK: - Zone Notifications (polling-based)

    private func checkZoneNotifications(devices: [RachioDevice]) async {
        let wantRan      = UserDefaults.standard.object(forKey: AppStorageKey.zoneStoppedEnabled)  as? Bool ?? false
        let wantUpcoming = UserDefaults.standard.object(forKey: AppStorageKey.scheduleRunEnabled)   as? Bool ?? false

        for device in devices {
            for zone in device.zones where zone.enabled {

                // Zone ran: detect change in lastWateredDate
                if wantRan, let lastWatered = zone.lastWateredDate {
                    let key = "notif_zone_last_watered_\(zone.id)"
                    let stored = UserDefaults.standard.integer(forKey: key)
                    if stored > 0 && lastWatered != stored {
                        let durationMin = (zone.lastWateredDuration ?? 0) / 60
                        Self.logger.info("Zone ran: \(zone.name) for \(durationMin)m")
                        NotificationService.shared.scheduleZoneRanAlert(
                            zoneId: zone.id, zoneName: zone.name, durationMinutes: durationMin)
                    }
                    UserDefaults.standard.set(lastWatered, forKey: key)
                }

                // Upcoming run: fire if next run is within 2 hours
                if wantUpcoming, let nextRun = device.nextRunDate(forZone: zone) {
                    let minutesUntil = Int(nextRun.timeIntervalSinceNow / 60)
                    if minutesUntil > 0 && minutesUntil <= 120 {
                        Self.logger.info("Upcoming run: \(zone.name) in \(minutesUntil)m")
                        NotificationService.shared.scheduleUpcomingRunAlert(
                            zoneId: zone.id, zoneName: zone.name, minutesUntil: minutesUntil)
                    }
                }
            }
        }
    }

    // MARK: - Zone Skip Alerts

    private func checkZoneSkips(devices: [RachioDevice]) async {
        do {
            for device in devices {
                let skips = try await RachioAPI.shared.getRainSkips(deviceId: device.id, days: 1)
                for skip in skips {
                    // Only alert on skips that are recent (within the last 2 refresh cycles ~30min)
                    let ageMinutes = Date().timeIntervalSince(skip.skipDate) / 60
                    guard ageMinutes >= 0 && ageMinutes <= 30 else { continue }
                    Self.logger.info("Zone skip alert: \(skip.scheduleName) — \(skip.reason)")
                    NotificationService.shared.scheduleZoneSkipAlert(
                        skipId: skip.id,
                        scheduleName: skip.scheduleName,
                        reason: skip.reason
                    )
                }
            }
        } catch {
            Self.logger.error("Zone skip check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Service Disconnected Alerts

    /// Fires if SenseCraft or Rachio hasn't had a successful connection in 2+ hours.
    /// This catches both auth failures and sustained network outages.
    private func checkServiceAlerts(visibleSensorCount: Int) {
        guard UserDefaults.standard.object(forKey: AppStorageKey.serviceAlertsEnabled) as? Bool ?? true else { return }

        let thresholdHours = 2.0
        let now = Date()

        // SenseCraft — only check if we have configured sensors
        if visibleSensorCount > 0 {
            if let lastSuccess = UserDefaults.standard.object(forKey: "notif_sensecraft_last_success") as? Date {
                let hoursOffline = now.timeIntervalSince(lastSuccess) / 3600
                if hoursOffline >= thresholdHours {
                    Self.logger.warning("SenseCraft offline for \(hoursOffline, format: .fixed(precision: 1))h")
                    NotificationService.shared.scheduleServiceAlert(service: "SenseCraft", hoursOffline: hoursOffline)
                }
            }
            // If no lastSuccess key at all, don't alert — app may just be newly installed
        }

        // Rachio — only check if API key is configured
        if KeychainService.shared.load(forKey: KeychainKey.rachioAPIKey) != nil {
            if let lastSuccess = UserDefaults.standard.object(forKey: "notif_rachio_last_success") as? Date {
                let hoursOffline = now.timeIntervalSince(lastSuccess) / 3600
                if hoursOffline >= thresholdHours {
                    Self.logger.warning("Rachio offline for \(hoursOffline, format: .fixed(precision: 1))h")
                    NotificationService.shared.scheduleServiceAlert(service: "Rachio", hoursOffline: hoursOffline)
                }
            }
        }
    }

    // MARK: - Daily Summary

    private func checkDailySummary(summary: SensorSummaryData) {
        guard summary.totalCount > 0, let driest = summary.driest else { return }

        let configuredHour   = UserDefaults.standard.integer(forKey: AppStorageKey.dailySummaryHour)
        let configuredMinute = UserDefaults.standard.integer(forKey: AppStorageKey.dailySummaryMinute)
        let cal  = Calendar.current
        let now  = Date()
        let hour = cal.component(.hour,   from: now)
        let min  = cal.component(.minute, from: now)

        // Only fire if it's past the configured time
        guard hour > configuredHour || (hour == configuredHour && min >= configuredMinute) else { return }

        // Only fire once per day
        if let lastSent = UserDefaults.standard.object(forKey: "notif_daily_summary_last_sent") as? Date,
           cal.isDateInToday(lastSent) { return }

        Self.logger.info("Sending daily summary: \(summary.healthy)H \(summary.low)L \(summary.critical)C")
        NotificationService.shared.sendDailySummary(
            healthy: summary.healthy, low: summary.low, critical: summary.critical,
            driestName: driest.name, driestMoisture: driest.moisture)
    }

    // MARK: - Weekly Report

    private func checkWeeklyReport(summary: SensorSummaryData) {
        guard summary.totalCount > 0 else { return }

        let targetWeekday = UserDefaults.standard.integer(forKey: AppStorageKey.weeklyReportDay) // 0=Sun
        let cal     = Calendar.current
        let today   = cal.component(.weekday, from: Date()) - 1 // convert to 0=Sun
        guard today == targetWeekday else { return }

        // Only fire once per week
        if let lastSent = UserDefaults.standard.object(forKey: "notif_weekly_report_last_sent") as? Date,
           cal.isDate(lastSent, equalTo: Date(), toGranularity: .weekOfYear) { return }

        let avg = summary.totalCount > 0 ? summary.totalMoisture / Double(summary.totalCount) : 0
        Self.logger.info("Sending weekly report: avg \(avg, format: .fixed(precision: 1))%")
        NotificationService.shared.sendWeeklyReport(
            totalSensors: summary.totalCount, avgMoisture: avg,
            lowCount: summary.low, criticalCount: summary.critical)
    }
}
