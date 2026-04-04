import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "com.rachiosense", category: "NotificationService")

final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            if !granted {
                logger.info("Permission denied by user")
            }
        } catch {
            logger.error("Error requesting permission: \(error.localizedDescription)")
        }
    }

    // MARK: - Cooldown

    private func cooldownKey(eui: String, type: String) -> String {
        "notif_last_sent_\(type)_\(eui)"
    }

    private func isOnCooldown(eui: String, type: String, cooldownHours: Int) -> Bool {
        let key = cooldownKey(eui: eui, type: type)
        guard let lastSent = UserDefaults.standard.object(forKey: key) as? Date else { return false }
        return Date().timeIntervalSince(lastSent) < Double(cooldownHours) * 3600
    }

    private func recordSent(eui: String, type: String) {
        UserDefaults.standard.set(Date(), forKey: cooldownKey(eui: eui, type: type))
    }

    // MARK: - Quiet Hours

    private func isQuietHours() -> Bool {
        guard UserDefaults.standard.bool(forKey: AppStorageKey.quietHoursEnabled) else { return false }
        let startHour = UserDefaults.standard.integer(forKey: AppStorageKey.quietHoursStartHour)
        let endHour   = UserDefaults.standard.integer(forKey: AppStorageKey.quietHoursEndHour)
        let hour      = Calendar.current.component(.hour, from: Date())
        // Handle overnight ranges (e.g. 22–7) and same-day ranges (e.g. 9–17)
        return startHour <= endHour
            ? (hour >= startHour && hour < endHour)
            : (hour >= startHour || hour < endHour)
    }

    // MARK: - Threshold Alert (already below dry / critical level)

    /// Fires when moisture has already crossed a threshold.
    /// Respects: toggle, quiet hours, per-sensor cooldown.
    func scheduleThresholdAlert(
        eui: String,
        sensorName: String,
        zoneName: String?,
        moisture: Double,
        isCritical: Bool
    ) {
        let toggleKey = isCritical ? AppStorageKey.dryAlertsEnabled : AppStorageKey.lowAlertsEnabled
        // Default true — treat a missing key as enabled
        let enabled = UserDefaults.standard.object(forKey: toggleKey) as? Bool ?? true
        guard enabled else { return }
        guard !isQuietHours() else {
            logger.info("Quiet hours — suppressing threshold alert for \(sensorName)")
            return
        }

        let type = isCritical ? "critical" : "low"
        guard !isOnCooldown(eui: eui, type: type, cooldownHours: effectiveCooldown()) else {
            logger.info("Cooldown active — suppressing \(type) alert for \(sensorName)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = isCritical ? "⚠️ Critical Soil Moisture" : "Soil Moisture Low"
        if let zoneName {
            content.body = "\(sensorName) is at \(Int(moisture))%. Consider running zone \"\(zoneName)\"."
        } else {
            content.body = "\(sensorName) is at \(Int(moisture))%."
        }
        content.sound = .default

        send(identifier: "moisture-\(type)-\(eui)", content: content) {
            self.recordSent(eui: eui, type: type)
        }
    }

    // MARK: - Predictive Alert (predicted to cross threshold within window)

    /// Fires when the exponential decay model predicts the sensor will cross a threshold
    /// within the configured alert window (default 6 h).
    func schedulePredictiveAlert(
        eui: String,
        sensorName: String,
        hoursRemaining: Double,
        isCritical: Bool
    ) {
        let enabled = UserDefaults.standard.object(forKey: AppStorageKey.predictiveAlertEnabled) as? Bool ?? true
        guard enabled else { return }
        guard !isQuietHours() else { return }

        let type = isCritical ? "predictive-critical" : "predictive-dry"
        guard !isOnCooldown(eui: eui, type: type, cooldownHours: effectiveCooldown()) else {
            logger.info("Cooldown active — suppressing predictive alert for \(sensorName)")
            return
        }

        let timeText: String
        if hoursRemaining < 1.0 {
            timeText = "~\(max(1, Int((hoursRemaining * 60).rounded())))m"
        } else {
            timeText = "~\(Int(hoursRemaining.rounded()))h"
        }

        let content = UNMutableNotificationContent()
        content.title = isCritical ? "⚠️ Going Critical Soon" : "Going Dry Soon"
        content.body  = "\(sensorName) will reach \(isCritical ? "critical" : "dry") in \(timeText)."
        content.sound = .default

        send(identifier: "moisture-\(type)-\(eui)", content: content) {
            self.recordSent(eui: eui, type: type)
        }
    }

    // MARK: - Service Disconnected Alert

    /// Fires when SenseCraft or Rachio hasn't connected successfully in `hoursOffline` hours.
    /// Uses a fixed 6h cooldown so it doesn't repeat every refresh while the outage persists.
    func scheduleServiceAlert(service: String, hoursOffline: Double) {
        let enabled = UserDefaults.standard.object(forKey: AppStorageKey.serviceAlertsEnabled) as? Bool ?? true
        guard enabled else { return }
        guard !isQuietHours() else { return }
        guard !isOnCooldown(eui: service, type: "service-down", cooldownHours: 6) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(service) Disconnected"
        content.body  = "RachioSense hasn't been able to reach \(service) in over \(Int(hoursOffline.rounded()))h. Check your credentials and network."
        content.sound = .default

        send(identifier: "service-down-\(service.lowercased())", content: content) {
            self.recordSent(eui: service, type: "service-down")
        }
    }

    // MARK: - Zone Skip Alert

    /// Fires when Rachio skips a scheduled zone run due to weather intelligence (rain, freeze, wind).
    func scheduleZoneSkipAlert(skipId: String, scheduleName: String, reason: String) {
        let enabled = UserDefaults.standard.object(forKey: AppStorageKey.zoneSkipEnabled) as? Bool ?? true
        guard enabled else { return }
        guard !isQuietHours() else { return }
        // Use skipId as the cooldown key so each unique skip event fires at most once
        guard !isOnCooldown(eui: skipId, type: "zone-skip", cooldownHours: 23) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Zone Run Skipped"
        content.body  = "\"\(scheduleName)\" was skipped — \(reason)."
        content.sound = .default

        send(identifier: "zone-skip-\(skipId)", content: content) {
            self.recordSent(eui: skipId, type: "zone-skip")
        }
    }

    // MARK: - Sensor Offline Alert

    func scheduleSensorOfflineAlert(eui: String, sensorName: String, hoursOffline: Double) {
        let enabled = UserDefaults.standard.object(forKey: AppStorageKey.sensorOfflineEnabled) as? Bool ?? true
        guard enabled else { return }
        guard !isQuietHours() else { return }
        // Offline state persists; 12h cooldown prevents repeated alerts during outages
        guard !isOnCooldown(eui: eui, type: "offline", cooldownHours: 12) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sensor Offline"
        content.body  = "\(sensorName) hasn't reported in over \(Int(hoursOffline.rounded()))h."
        content.sound = .default

        send(identifier: "sensor-offline-\(eui)", content: content) {
            self.recordSent(eui: eui, type: "offline")
        }
    }

    // MARK: - Zone Ran Alert

    /// Fires when a zone's lastWateredDate changed since the previous background refresh,
    /// indicating a watering cycle completed.
    func scheduleZoneRanAlert(zoneId: String, zoneName: String, durationMinutes: Int) {
        let enabled = UserDefaults.standard.object(forKey: AppStorageKey.zoneStoppedEnabled) as? Bool ?? false
        guard enabled else { return }
        // 1h cooldown — zones rarely run back-to-back
        guard !isOnCooldown(eui: zoneId, type: "zone-ran", cooldownHours: 1) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Zone Finished"
        let mins = durationMinutes == 1 ? "1 minute" : "\(durationMinutes) minutes"
        content.body  = "\"\(zoneName)\" ran for \(mins)."
        content.sound = .default

        send(identifier: "zone-ran-\(zoneId)", content: content) {
            self.recordSent(eui: zoneId, type: "zone-ran")
        }
    }

    // MARK: - Upcoming Scheduled Run Alert

    func scheduleUpcomingRunAlert(zoneId: String, zoneName: String, minutesUntil: Int) {
        let enabled = UserDefaults.standard.object(forKey: AppStorageKey.scheduleRunEnabled) as? Bool ?? false
        guard enabled else { return }
        // Cooldown = effective cooldown — prevents re-alerting every refresh cycle for same run
        guard !isOnCooldown(eui: zoneId, type: "upcoming-run", cooldownHours: effectiveCooldown()) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Scheduled Run Soon"
        let timeText = minutesUntil < 5 ? "a few minutes" : "\(minutesUntil) minutes"
        content.body  = "\"\(zoneName)\" is scheduled to run in \(timeText)."
        content.sound = .default

        send(identifier: "upcoming-run-\(zoneId)", content: content) {
            self.recordSent(eui: zoneId, type: "upcoming-run")
        }
    }

    // MARK: - Daily Summary

    func sendDailySummary(healthy: Int, low: Int, critical: Int, driestName: String, driestMoisture: Double) {
        var parts: [String] = []
        if healthy > 0  { parts.append("\(healthy) healthy") }
        if low > 0      { parts.append("\(low) low") }
        if critical > 0 { parts.append("\(critical) critical") }

        let content = UNMutableNotificationContent()
        content.title = "RachioSense Daily Summary"
        content.body  = "\(parts.joined(separator: " · ")) · driest: \(driestName) at \(Int(driestMoisture))%"
        content.sound = .default

        send(identifier: "daily-summary", content: content) {
            UserDefaults.standard.set(
                Calendar.current.startOfDay(for: Date()),
                forKey: "notif_daily_summary_last_sent"
            )
        }
    }

    // MARK: - Weekly Report

    func sendWeeklyReport(totalSensors: Int, avgMoisture: Double, lowCount: Int, criticalCount: Int) {
        let statusLine: String
        if criticalCount > 0 {
            statusLine = "\(criticalCount) sensor\(criticalCount == 1 ? "" : "s") at critical level"
        } else if lowCount > 0 {
            statusLine = "\(lowCount) sensor\(lowCount == 1 ? "" : "s") running low"
        } else {
            statusLine = "All \(totalSensors) sensors healthy"
        }

        let content = UNMutableNotificationContent()
        content.title = "RachioSense Weekly Report"
        content.body  = "\(statusLine). Average moisture: \(Int(avgMoisture.rounded()))%."
        content.sound = .default

        send(identifier: "weekly-report", content: content) {
            UserDefaults.standard.set(Date(), forKey: "notif_weekly_report_last_sent")
        }
    }

    // MARK: - Clear Badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error {
                logger.error("Failed to clear badge: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Helpers

    private func effectiveCooldown() -> Int {
        let stored = UserDefaults.standard.integer(forKey: AppStorageKey.notificationCooldownHours)
        return stored > 0 ? stored : 4
    }

    private func send(identifier: String, content: UNMutableNotificationContent, onSuccess: @escaping @Sendable () -> Void) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to deliver '\(identifier)': \(error.localizedDescription)")
            } else {
                onSuccess()
            }
        }
    }
}
