import Foundation

/// Auth API service uses a separate APIClient without auth interceptor
/// to avoid circular dependency (same pattern as Android's NetworkModule).
struct AuthAPIService: Sendable {
    private let client: APIClient

    init(baseURL: URL = Constants.baseURL, deviceIdProvider: @Sendable @escaping () async -> String?) {
        self.client = APIClient(
            baseURL: baseURL,
            tokenProvider: nil,
            deviceIdProvider: deviceIdProvider
        )
    }

    func login(email: String, password: String, deviceId: String, deviceName: String?) async throws -> DeviceAuthResponse {
        let body = DeviceLoginRequest(
            email: email,
            password: password,
            deviceId: deviceId,
            deviceName: deviceName
        )
        return try await client.request(Endpoint(
            path: "auth/device-login",
            method: .post,
            body: body
        ))
    }

    func refresh(refreshToken: String, deviceId: String) async throws -> DeviceAuthResponse {
        let body = DeviceRefreshRequest(
            refreshToken: refreshToken,
            deviceId: deviceId
        )
        return try await client.request(Endpoint(
            path: "auth/device-refresh",
            method: .post,
            body: body
        ))
    }

    func forgotPassword(email: String) async throws -> ForgotPasswordResponse {
        let body = ForgotPasswordRequest(email: email)
        return try await client.request(Endpoint(
            path: "auth/forgot-password",
            method: .post,
            body: body
        ))
    }
}
