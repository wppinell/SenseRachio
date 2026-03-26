import Foundation
import SwiftData

@Model
class SensorConfig {
    var id: String
    var name: String          // Original name from API
    var alias: String?        // User-defined alias
    var eui: String
    var linkedZoneId: String?
    var moistureThreshold: Double?
    var autoWaterEnabled: Bool
    var groupId: String?
    var isHiddenFromGraphs: Bool
    var subscriptionExpiryDate: Date?
    
    /// Days until subscription expires (nil if unknown)
    var daysUntilExpiry: Int? {
        guard let expiry = subscriptionExpiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }

    /// Display name: alias if set, otherwise original name
    var displayName: String {
        if let alias = alias, !alias.isEmpty {
            return alias
        }
        return name
    }

    init(id: String, name: String, eui: String, alias: String? = nil, linkedZoneId: String? = nil,
         moistureThreshold: Double? = nil, autoWaterEnabled: Bool = false,
         groupId: String? = nil, isHiddenFromGraphs: Bool = false, subscriptionExpiryDate: Date? = nil) {
        self.id = id
        self.name = name
        self.alias = alias
        self.eui = eui
        self.linkedZoneId = linkedZoneId
        self.moistureThreshold = moistureThreshold
        self.autoWaterEnabled = autoWaterEnabled
        self.groupId = groupId
        self.isHiddenFromGraphs = isHiddenFromGraphs
        self.subscriptionExpiryDate = subscriptionExpiryDate
    }
}

@Model
class ZoneConfig {
    var id: String
    var name: String
    var deviceId: String
    var lastRunAt: Date?

    init(id: String, name: String, deviceId: String, lastRunAt: Date? = nil) {
        self.id = id
        self.name = name
        self.deviceId = deviceId
        self.lastRunAt = lastRunAt
    }
}

@Model
class SensorReading {
    var eui: String
    var moisture: Double
    var tempC: Double
    var recordedAt: Date

    init(eui: String, moisture: Double, tempC: Double, recordedAt: Date = Date()) {
        self.eui = eui
        self.moisture = moisture
        self.tempC = tempC
        self.recordedAt = recordedAt
    }
}

@Model
class ZoneGroup {
    var id: String
    var name: String
    var iconName: String
    var sortOrder: Int
    var assignedZoneIds: [String]

    init(id: String = UUID().uuidString, name: String, iconName: String = "circle.hexagongrid",
         sortOrder: Int = 0, assignedZoneIds: [String] = []) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.assignedZoneIds = assignedZoneIds
    }
}

@Model
class DashboardCardOrder {
    var cards: [String]  // ordered card IDs
    var hiddenCards: [String]

    init(cards: [String] = ["moisture", "zones", "weather", "history", "schedule"],
         hiddenCards: [String] = []) {
        self.cards = cards
        self.hiddenCards = hiddenCards
    }
}
