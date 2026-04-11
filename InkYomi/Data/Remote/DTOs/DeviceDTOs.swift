import Foundation

struct DeviceRegisterRequest: Encodable {
    let deviceName: String
    let deviceModel: String?
    let platform: String
    let publicKeyPem: String
    let deviceIdentifier: String?
}

struct DeviceRegisterResponse: Decodable {
    let deviceId: String
}

struct DeviceListResponse: Decodable {
    let devices: [DeviceDto]
}

struct DeviceDto: Decodable {
    let id: String
    let deviceName: String
    let deviceModel: String?
    let platform: String
    let registeredAt: String?
    let lastSeenAt: String?
    let isCurrent: Bool?

    func toDomain() -> Device {
        let formatter = ISO8601DateFormatter()
        return Device(
            id: id,
            deviceName: deviceName,
            deviceModel: deviceModel,
            platform: platform,
            registeredAt: registeredAt.flatMap { formatter.date(from: $0) },
            lastSeenAt: lastSeenAt.flatMap { formatter.date(from: $0) },
            isCurrent: isCurrent ?? false
        )
    }
}
