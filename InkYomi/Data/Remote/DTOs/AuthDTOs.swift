import Foundation

// Requests use snake_case keys (server expects them)
struct DeviceLoginRequest: Encodable {
    let email: String
    let password: String
    let deviceId: String
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case email, password
        case deviceId = "device_id"
        case deviceName = "device_name"
    }
}

struct DeviceRefreshRequest: Encodable {
    let refreshToken: String
    let deviceId: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case deviceId = "device_id"
    }
}

struct ForgotPasswordRequest: Encodable {
    let email: String
}

// Response uses camelCase keys (server returns them as-is)
struct DeviceAuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int64        // epoch millis, not ISO string
    let refreshExpiresAt: Int64
    let user: UserDTO
    let deviceRegistrationId: String?
}

struct UserDTO: Decodable {
    let id: String
    let email: String
    let displayName: String?

    func toDomain() -> UserProfile {
        UserProfile(id: id, email: email, displayName: displayName)
    }
}

struct ForgotPasswordResponse: Decodable {
    let ok: Bool
}
