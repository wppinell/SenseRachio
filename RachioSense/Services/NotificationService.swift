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
