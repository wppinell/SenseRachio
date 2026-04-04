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

    // MARK: - Schedule Low Moisture Notification

    func scheduleNotification(sensorName: String, zoneName: String?, moisture: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Low Soil Moisture Alert"

        if let zoneName = zoneName {
            content.body = "\(sensorName) moisture is at \(Int(moisture))%. Consider running zone \"\(zoneName)\"."
        } else {
            content.body = "\(sensorName) moisture is at \(Int(moisture))%."
        }
        content.sound = .default
        content.badge = 1

        // Unique identifier per sensor so we don't spam
        let identifier = "moisture-alert-\(sensorName.lowercased().replacingOccurrences(of: " ", with: "-"))"

        // Deliver immediately (trigger = nil for immediate delivery)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Clear Badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                logger.error("Failed to clear badge: \(error.localizedDescription)")
            }
        }
    }
}
