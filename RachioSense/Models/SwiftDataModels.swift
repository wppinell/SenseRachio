import Foundation
import SwiftData

@Model
class SensorConfig {
    var id: String
    var name: String
    var eui: String
    var linkedZoneId: String?
    var moistureThreshold: Double?
    var autoWaterEnabled: Bool
    var groupId: String?
    var isHiddenFromGraphs: Bool

    init(id: String, name: String, eui: String, linkedZoneId: String? = nil,
         moistureThreshold: Double? = nil, autoWaterEnabled: Bool = false,
         groupId: String? = nil, isHiddenFromGraphs: Bool = false) {
        self.id = id
        self.name = name
        self.eui = eui
        self.linkedZoneId = linkedZoneId
        self.moistureThreshold = moistureThreshold
        self.autoWaterEnabled = autoWaterEnabled
        self.groupId = groupId
        self.isHiddenFromGraphs = isHiddenFromGraphs
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
class SensorGroup {
    var id: String
    var name: String
    var iconName: String
    var sortOrder: Int
    var assignedSensorIds: [String]
    var assignedZoneIds: [String]

    init(id: String = UUID().uuidString, name: String, iconName: String = "circle.hexagongrid",
         sortOrder: Int = 0, assignedSensorIds: [String] = [], assignedZoneIds: [String] = []) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.assignedSensorIds = assignedSensorIds
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
