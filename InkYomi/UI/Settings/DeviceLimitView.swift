import SwiftUI

/// Non-blocking sheet shown after a sign-in where the backend reported the
/// account is already at its 5-device cap (`deviceLimitReached`). The user
/// is signed in regardless; this device just wasn't registered. We explain
/// the situation, let the user revoke an existing device inline, and then
/// retry registering this device — all without leaving the sheet.
///
/// Reuses `DeviceListViewModel` (the same view model backing the Settings
/// device manager) so revoke + register behavior stays in one place.
struct DeviceLimitView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = DeviceListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            explainer
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }

                        if viewModel.didRegister {
                            Section {
                                Label("This device is now registered.", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline)
                            }
                        } else if !viewModel.isAtDeviceLimit {
                            // A slot opened up (user revoked one) — offer retry.
                            Section {
                                Button {
                                    Task { await viewModel.registerCurrentDevice() }
                                } label: {
                                    HStack {
                                        if viewModel.isRegistering {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "plus.circle")
                                        }
                                        Text("Register this device")
                                    }
                                }
                                .disabled(viewModel.isRegistering)
                            } footer: {
                                Text("A slot is free. Register this device to read on it.")
                            }
                        }

                        Section("Your devices") {
                            ForEach(viewModel.devices) { device in
                                deviceRow(device)
                            }
                        }

                        if let error = viewModel.error {
                            Section {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(Color.inkError)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Device limit reached")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.didRegister ? "Done" : "Not now") { dismiss() }
                }
            }
            .task {
                viewModel.configure(deviceRepository: container.deviceRepository)
                await viewModel.loadDevices()
            }
        }
    }

    @ViewBuilder
    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.iphone")
                .font(.title)
                .foregroundStyle(Color.inkPrimary)
            Text("You're signed in, but this device wasn't registered.")
                .font(.headline)
            Text("Your account is limited to \(DeviceListViewModel.maxDevices) devices. Remove one below to free a slot, then register this device so you can download and read your books on it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func deviceRow(_ device: Device) -> some View {
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
