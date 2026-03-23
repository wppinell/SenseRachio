import Foundation

// MARK: - SenseCraft API Response Models

// /list_devices response:
// { "code": "0", "data": [ { "device_eui": "...", "device_name": "..." } ] }
struct SenseCraftListDevicesResponse: Codable {
    let code: String?
    let data: [SenseCraftDeviceItem]?
    let msg: String?
}

struct SenseCraftDeviceItem: Codable {
    let deviceEui: String
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case deviceEui = "device_eui"
        case deviceName = "device_name"
    }
}

// /view_latest_telemetry_data response:
// { "code": "0", "data": [ { "channel_index": 1, "points": [ { "measurement_id": "4103", "measurement_value": 21.5, "time": "..." } ] } ] }
struct SenseCraftTelemetryResponse: Codable {
    let code: String?
    let data: [SenseCraftChannel]?
    let msg: String?
}

struct SenseCraftChannel: Codable {
    let channelIndex: Int?
    let points: [SenseCraftPoint]?

    enum CodingKeys: String, CodingKey {
        case channelIndex = "channel_index"
        case points
    }
}

struct SenseCraftPoint: Codable {
    let measurementId: String
    let measurementValue: Double?   // API returns number, not string
    let time: String?

    enum CodingKeys: String, CodingKey {
        case measurementId = "measurement_id"
        case measurementValue = "measurement_value"
        case time
    }
}

// MARK: - Rachio API Response Models

struct RachioPersonInfoResponse: Codable {
    let id: String
    let username: String?
    let email: String?
}

struct RachioPersonResponse: Codable {
    let id: String
    let devices: [RachioPersonDeviceEntry]?
}

struct RachioPersonDeviceEntry: Codable {
    let id: String
}

struct RachioZoneStartRequest: Codable {
    let id: String
    let duration: Int
}

struct RachioZoneStopRequest: Codable {
    let id: String
}
