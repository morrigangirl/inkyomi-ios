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

    /// Two-step convenience: list devices, find the row flagged
    /// `isCurrent` server-side (matched by deviceIdentifier), revoke
    /// it. The server marks at most one row as current per request,
    /// so this is unambiguous in steady state.
    ///
    /// If the GET fails (offline) or no row is flagged current, this
    /// throws so the caller — typically Settings → "Remove this
    /// device" — can decide whether to still wipe locally. The
    /// caller's contract is: wipe locally regardless; the server
    /// will reconcile on the next reconnect via the lazy bounce.
    func revokeCurrentDevice() async throws {
        let devices = try await api.getDevices().devices
        // Map the server's deviceIdentifier (UUID minted client-side)
        // to the row whose isCurrent flag is true. The server
        // computes isCurrent by matching the incoming X-Device-Id
        // header against the row's deviceIdentifier — so the row's
        // own id is what we need to DELETE.
        guard let row = devices.first(where: { $0.isCurrent == true }) else {
            throw DeviceRevocationError.noCurrentDeviceRow
        }
        try await api.revokeDevice(id: row.id)
    }
}

enum DeviceRevocationError: LocalizedError {
    case noCurrentDeviceRow
    var errorDescription: String? {
        switch self {
        case .noCurrentDeviceRow:
            return "Couldn't find this device in your registered list — it may already be removed."
        }
    }
}
