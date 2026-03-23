import Foundation
import SwiftData

@Model
class SensorConfig {
    var id: String
    var name: String
    var eui: String
    var linkedZoneId: String?
    var moistureThreshold: Double?

    init(id: String, name: String, eui: String, linkedZoneId: String? = nil, moistureThreshold: Double? = nil) {
        self.id = id
        self.name = name
        self.eui = eui
        self.linkedZoneId = linkedZoneId
        self.moistureThreshold = moistureThreshold
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
