import Foundation

struct Device: Identifiable, Equatable, Sendable {
    let id: String
    let deviceName: String
    let deviceModel: String?
    let platform: String
    let registeredAt: Date?
    let lastSeenAt: Date?
    let isCurrent: Bool
}

protocol DeviceRepository: Sendable {
    func ensureRegistered() async throws
    func getDevices() async throws -> [Device]
    func revokeDevice(id: String) async throws
    /// Convenience: look up which device row corresponds to *this*
    /// install (`isCurrent == true`) and revoke it. Used by the
    /// Settings "Remove this device" button — pairs with a local
    /// `UserDataWipe.wipe()` call to clear on-disk state.
    func revokeCurrentDevice() async throws
}
