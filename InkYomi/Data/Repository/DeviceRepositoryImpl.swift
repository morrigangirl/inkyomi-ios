import Foundation
import UIKit

struct DeviceRepositoryImpl: DeviceRepository, Sendable {
    private let api: DeviceAPIService
    private let appState: AppState

    init(api: DeviceAPIService, appState: AppState) {
        self.api = api
        self.appState = appState
    }

    func ensureRegistered() async throws {
        let publicKeyPem = try DeviceKeyManager.publicKeyPEM()
        let deviceName = await MainActor.run { UIDevice.current.model }
        let request = DeviceRegisterRequest(
            deviceName: deviceName,
            deviceModel: deviceName,
            platform: "ios",
            publicKeyPem: publicKeyPem,
            deviceIdentifier: await MainActor.run { appState.deviceId }
        )
        _ = try await api.register(request: request)
    }

    func getDevices() async throws -> [Device] {
        let response = try await api.getDevices()
        // The backend computes `is_current` by comparing each row's PK
        // (`user_devices.id`) against the `X-Device-Id` request header.
        // But this client sends its *device identifier* in that header
        // (which the server stores as `device_identifier`, not `id`), so
        // the server's `is_current` is never true for us. Recompute it
        // locally against the registration id (the row PK) the server
        // handed us at login — the identifier space the server actually
        // compares against.
        let localRegistrationId = await MainActor.run { appState.deviceRegistrationId }
        return response.devices.map { dto in
            dto.toDomain(currentRegistrationId: localRegistrationId)
        }
    }

    func revokeDevice(id: String) async throws {
        try await api.revokeDevice(id: id)
    }
}
