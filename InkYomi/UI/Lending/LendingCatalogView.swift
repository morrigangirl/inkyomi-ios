import SwiftUI

struct LendingCatalogView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var viewModel = LendingCatalogViewModel()

    var onBorrowSuccess: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search books...", text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.onSearchQueryChanged($0) }
                ))
                .textFieldStyle(.plain)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.onSearchQueryChanged("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Content
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error, viewModel.publications.isEmpty {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await viewModel.loadCatalog() }
                        }
                    }
                } else if viewModel.publications.isEmpty {
                    ContentUnavailableView(
                        viewModel.searchQuery.isEmpty
                            ? "No Books Available"
                            : "No Results",
                        systemImage: "books.vertical",
                        description: Text(
                            viewModel.searchQuery.isEmpty
                                ? "Check back later for new titles"
                                : "Try a different search term"
                        )
                    )
                } else {
                    catalogGrid
                }
            }
        }
        .navigationTitle("Lending Library")
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.configure(
                lendingRepository: container.lendingRepository,
                libraryRepository: container.libraryRepository
            )
            await viewModel.loadCatalog()
        }
        .onChange(of: viewModel.borrowSuccess) { _, success in
            if success, let bookId = viewModel.lastBorrowedBookId {
                viewModel.clearBorrowSuccess()
                onBorrowSuccess?(bookId)
            }
        }
    }

    private var catalogGrid: some View {
        let cardRange = GridColumns.adaptiveRange(for: hSizeClass)
        return ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: cardRange.min, maximum: cardRange.max), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.publications) { pub in
                    LendingBookCard(
                        publication: pub,
                        isBorrowing: viewModel.borrowingBookId == pub.extractBookId,
                        alreadyOwned: false,
                        onBorrow: {
                            if let bookId = pub.extractBookId {
                                viewModel.borrowBook(bookId: bookId)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Lending Book Card

private struct LendingBookCard: View {
    let publication: OpdsPublication
    let isBorrowing: Bool
    let alreadyOwned: Bool
    let onBorrow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cover image
            let coverUrl = publication.images?.first?.href
            BookCoverView(url: resolvedCoverUrl(coverUrl), width: nil, height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Title
            Text(publication.metadata.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Author
            if let author = publication.metadata.author?.first?.name {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Borrow button
            if alreadyOwned {
                Button {} label: {
                    Text("Already in your library")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            } else {
                Button(action: onBorrow) {
                    Group {
                        if isBorrowing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Borrowing...")
                            }
                        } else {
                            Text("Borrow")
                        }
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.inkPrimary)
                .disabled(isBorrowing)
            }
        }
    }

    private func resolvedCoverUrl(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return path }
        if path.hasPrefix("/") { return "https://inkcolors.shop\(path)" }
        return "https://inkcolors.shop/\(path)"
    }
}
