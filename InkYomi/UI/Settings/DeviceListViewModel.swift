import Foundation
import Observation

@MainActor @Observable
final class DeviceListViewModel {
    /// Backend caps active devices per account at 5.
    static let maxDevices = 5

    var devices: [Device] = []
    var isLoading = false
    var error: String?

    /// Drives the optional "register this device" affordance used by the
    /// device-limit flow. `isRegistering` gates the spinner; `didRegister`
    /// flips true on a successful (re)registration so callers can confirm.
    var isRegistering = false
    var didRegister = false

    private var deviceRepository: (any DeviceRepository)?

    /// True when the account is at the cap, so a new device can't be
    /// registered until one is revoked.
    var isAtDeviceLimit: Bool { devices.count >= Self.maxDevices }

    func configure(deviceRepository: any DeviceRepository) {
        self.deviceRepository = deviceRepository
    }

    func loadDevices() async {
        guard let deviceRepository else { return }
        isLoading = true
        do {
            devices = try await deviceRepository.getDevices()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func revokeDevice(id: String) async {
        guard let deviceRepository else { return }
        do {
            try await deviceRepository.revokeDevice(id: id)
            devices.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Retry registering the current device — used after the user frees a
    /// slot from the device-limit prompt. Re-fetches the list afterward so
    /// "This device" surfaces. Best-effort: failures surface in `error`.
    func registerCurrentDevice() async {
        guard let deviceRepository else { return }
        isRegistering = true
        error = nil
        do {
            try await deviceRepository.ensureRegistered()
            didRegister = true
            devices = try await deviceRepository.getDevices()
        } catch {
            self.error = error.localizedDescription
        }
        isRegistering = false
    }
}
