import Foundation
import Observation

@Observable
@MainActor
final class ProfileViewModel {
    var deviceCount: Int?
    var isLoadingDevices: Bool = false

    private var deviceRepository: (any DeviceRepository)?

    func configure(deviceRepository: any DeviceRepository) {
        self.deviceRepository = deviceRepository
    }

    func loadDeviceCount() async {
        guard let deviceRepository else { return }
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        do {
            let devices = try await deviceRepository.getDevices()
            deviceCount = devices.count
        } catch {
            // Best-effort — if we can't fetch, the row falls back to a
            // generic "Manage your registered devices" subtitle.
            deviceCount = nil
        }
    }
}
