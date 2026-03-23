import Foundation

// MARK: - SenseCraft API Response Models

struct SenseCraftListDevicesResponse: Codable {
    let code: String?
    let data: SenseCraftDeviceData?
    let msg: String?
}

struct SenseCraftDeviceData: Codable {
    let list: [SenseCraftDeviceItem]?
}

struct SenseCraftDeviceItem: Codable {
    let deviceEui: String
    let deviceName: String?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case deviceEui = "device_eui"
        case deviceName = "device_name"
        case status
    }
}

struct SenseCraftTelemetryResponse: Codable {
    let code: String?
    let data: [SenseCraftMeasurement]?
    let msg: String?
}

struct SenseCraftMeasurement: Codable {
    let measurementId: String
    let measurementValue: String?

    enum CodingKeys: String, CodingKey {
        case measurementId = "measurement_id"
        case measurementValue = "measurement_value"
    }
}

// MARK: - Rachio API Response Models

struct RachioPersonInfoResponse: Codable {
    let id: String
    let username: String?
    let email: String?
}

struct RachioDeviceListResponse: Codable {
    // The /person/{id}/device endpoint returns a JSON array directly
}

struct RachioZoneStartRequest: Codable {
    let id: String
    let duration: Int
}

struct RachioZoneStopRequest: Codable {
    let id: String
}
