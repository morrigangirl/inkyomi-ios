import Foundation
import Observation

@MainActor @Observable
final class DeviceListViewModel {
    var devices: [Device] = []
    var isLoading = false
    var error: String?

    private var deviceRepository: (any DeviceRepository)?

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
}
