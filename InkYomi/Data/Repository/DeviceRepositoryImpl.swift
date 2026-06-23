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
        // device_name = the user's name for the device ("Aoibh's iPhone"); on
        // iOS 16+ UIDevice.current.name only returns that with the
        // `com.apple.developer.device-information.user-assigned-device-name`
        // entitlement, else it falls back to the generic model ("iPhone").
        // device_model = the marketing model ("iPhone 16 Pro Max"), so the
        // device list shows both. platform = "ios".
        let deviceName = await MainActor.run { UIDevice.current.name }
        let request = DeviceRegisterRequest(
            deviceName: deviceName,
            deviceModel: DeviceModelName.marketingName,
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

/// Maps the raw hardware identifier (e.g. "iPhone17,2") to a marketing name
/// (e.g. "iPhone 16 Pro Max") for the device list, shown alongside the
/// user-assigned device name. Falls back to the raw identifier for models not
/// yet in the table (accurate, just not pretty) — extend it as new models ship.
enum DeviceModelName {
    /// Raw hardware identifier. On the simulator the real model id is in the
    /// `SIMULATOR_MODEL_IDENTIFIER` env var; on device it's `utsname.machine`.
    static var identifier: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty {
            return sim
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw -> String in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var marketingName: String {
        switch identifier {
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,5": return "iPhone 16e"
        // Newer models (iPhone 17 line, iPhone18,x and up) fall back to the raw
        // identifier until added here.
        default: return identifier
        }
    }
}
