import SwiftUI
import Observation

@Observable
@MainActor
final class StorageViewModel {
    var stats: StorageStats?
    var isClearing: Bool = false
    var lastFreedBytes: Int64?

    private var repository: StorageRepository?

    func configure(repository: StorageRepository) {
        self.repository = repository
    }

    func refresh() async {
        guard let repository else { return }
        stats = await repository.stats()
    }

    func clearBorrowed() async {
        guard let repository else { return }
        isClearing = true
        defer { isClearing = false }
        let freed = await repository.clearBorrowed()
        lastFreedBytes = freed
        stats = await repository.stats()
    }
}

struct StorageView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel = StorageViewModel()
    @State private var showConfirmClear = false
    @State private var showFreedToast = false

    var body: some View {
        List {
            Section {
                statRow(
                    label: "Owned books",
                    bytes: viewModel.stats?.ownedBytes,
                    count: viewModel.stats?.ownedCount
                )
                statRow(
                    label: "Borrowed books",
                    bytes: viewModel.stats?.borrowedBytes,
                    count: viewModel.stats?.borrowedCount
                )
            }

            Section {
                statRow(
                    label: "Total",
                    bytes: viewModel.stats?.totalBytes,
                    count: (viewModel.stats?.ownedCount ?? 0) + (viewModel.stats?.borrowedCount ?? 0),
                    emphasized: true
                )
            }

            Section {
                Button(role: .destructive) {
                    showConfirmClear = true
                } label: {
                    HStack {
                        Spacer()
                        Text(viewModel.isClearing ? "Clearing…" : "Clear borrowed downloads")
                        Spacer()
                    }
                }
                .disabled(viewModel.isClearing || (viewModel.stats?.borrowedBytes ?? 0) == 0)
            } footer: {
                Text("Owned-book downloads aren't cleared from this screen — re-downloading them costs your data and is needed for offline reading. Manage individual owned books from the Library.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(repository: container.storageRepository)
            await viewModel.refresh()
        }
        .alert("Clear borrowed downloads?", isPresented: $showConfirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await viewModel.clearBorrowed()
                    showFreedToast = true
                }
            }
        } message: {
            Text("Removes the cached EPUB files for borrowed books. Active loans will re-download the next time you open them. Your reading progress, bookmarks, and highlights are not affected.")
        }
        .overlay {
            if showFreedToast, let freed = viewModel.lastFreedBytes {
                snackbar("Freed \(StorageStats.format(freed))")
            }
        }
    }

    private func statRow(label: String, bytes: Int64?, count: Int?, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .headline : .body)
            Spacer()
            VStack(alignment: .trailing) {
                Text(bytes.map { StorageStats.format($0) } ?? "—")
                    .font(emphasized ? .headline : .body)
                if let count, count > 0 {
                    Text(count == 1 ? "1 file" : "\(count) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func snackbar(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .adaptiveMaterial()
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 30)
        }
        .transition(.move(edge: .bottom))
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(2))
                showFreedToast = false
            }
        }
    }
}
