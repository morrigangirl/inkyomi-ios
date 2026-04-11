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
        return response.devices.map { $0.toDomain() }
    }

    func revokeDevice(id: String) async throws {
        try await api.revokeDevice(id: id)
    }
}
