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

    /// - Parameter currentRegistrationId: the `user_devices.id` the server
    ///   assigned to this device at login. When present, `isCurrent` is
    ///   computed locally (row PK match) because the server's own
    ///   `is_current` flag compares against the wrong identifier. Falls
    ///   back to the server value when we don't yet know our row id.
    func toDomain(currentRegistrationId: String? = nil) -> Device {
        let formatter = ISO8601DateFormatter()
        let resolvedIsCurrent: Bool
        if let currentRegistrationId {
            resolvedIsCurrent = (id == currentRegistrationId)
        } else {
            resolvedIsCurrent = isCurrent ?? false
        }
        return Device(
            id: id,
            deviceName: deviceName,
            deviceModel: deviceModel,
            platform: platform,
            registeredAt: registeredAt.flatMap { formatter.date(from: $0) },
            lastSeenAt: lastSeenAt.flatMap { formatter.date(from: $0) },
            isCurrent: resolvedIsCurrent
        )
    }
}
