import SwiftUI

struct DeviceListView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel = DeviceListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.devices.isEmpty {
                ContentUnavailableView("No Devices", systemImage: "iphone", description: Text("No registered devices found."))
            } else {
                List(viewModel.devices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(device.deviceName)
                                    .font(.subheadline.weight(.medium))
                                if device.isCurrent {
                                    Text("This device")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.inkPrimary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(device.platform)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !device.isCurrent {
                            Button("Revoke", role: .destructive) {
                                Task { await viewModel.revokeDevice(id: device.id) }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Devices")
        .task {
            viewModel.configure(deviceRepository: container.deviceRepository)
            await viewModel.loadDevices()
        }
    }
}
