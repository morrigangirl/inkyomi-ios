import SwiftUI

struct LibraryView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var viewModel = LibraryViewModel()
    @State private var readerBookId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker — only show if lending is enabled
            if viewModel.lendingEnabled {
                Picker("Tab", selection: Binding(
                    get: { viewModel.selectedTab },
                    set: { viewModel.onTabChanged($0) }
                )) {
                    ForEach(LibraryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }

            // Content
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    switch viewModel.selectedTab {
                    case .owned:
                        ownedGrid
                    case .borrowed:
                        borrowedGrid
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle("My Books")
        .toolbar {
            if viewModel.lendingEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: LibraryRoute.lendingCatalog) {
                        Image(systemName: "building.columns")
                    }
                }
            }
        }
        .task {
            viewModel.configure(
                libraryRepository: container.libraryRepository,
                lendingRepository: container.lendingRepository
            )
            await viewModel.initialLoad()
        }
        .fullScreenCover(isPresented: Binding(
            get: { readerBookId != nil },
            set: { if !$0 { readerBookId = nil } }
        )) {
            if let bookId = readerBookId {
                ReaderView(bookId: bookId)
                    .environment(container)
                    .modelContainer(container.modelContainer)
            }
        }
        .overlay {
            if let message = viewModel.message {
                snackbar(message)
            }
        }
    }

    // MARK: - Owned Grid

    private var ownedGrid: some View {
        Group {
            if viewModel.ownedBooks.isEmpty {
                ContentUnavailableView(
                    "No Owned Books",
                    systemImage: "books.vertical",
                    description: Text("Books you purchase will appear here.")
                )
            } else {
                let thumbRange = GridColumns.adaptiveThumbRange(for: hSizeClass)
                let coverWidth = CoverSize.continueRow.width(for: hSizeClass)
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: thumbRange.min, maximum: thumbRange.max), spacing: 16)
                    ], spacing: 16) {
                        ForEach(viewModel.ownedBooks) { book in
                            NavigationLink(value: book.id) {
                                VStack(spacing: 4) {
                                    BookCoverView(
                                        url: book.coverUrl,
                                        width: coverWidth,
                                        height: CoverSize.continueRow.height(for: hSizeClass)
                                    )
                                    Text(book.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    if let author = book.authorName {
                                        Text(author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Borrowed Grid

    private var borrowedGrid: some View {
        Group {
            if viewModel.borrowedBooks.isEmpty {
                ContentUnavailableView {
                    Label("No Borrowed Books", systemImage: "books.vertical")
                } description: {
                    Text("Books you borrow will appear here.")
                } actions: {
                    NavigationLink(value: LibraryRoute.lendingCatalog) {
                        Text("Browse Lending Library")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.inkPrimary)
                }
            } else {
                let cardRange = GridColumns.adaptiveRange(for: hSizeClass)
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: cardRange.min, maximum: cardRange.max), spacing: 16)
                    ], spacing: 20) {
                        ForEach(viewModel.borrowedBooks) { loan in
                            BorrowedBookCard(
                                loan: loan,
                                onRead: {
                                    readerBookId = loan.bookId
                                },
                                onReturn: {
                                    viewModel.returnConfirmLoanId = loan.loanId
                                },
                                onRenew: {
                                    viewModel.renewBook(loanId: loan.loanId)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("Return Book?", isPresented: Binding(
            get: { viewModel.returnConfirmLoanId != nil },
            set: { if !$0 { viewModel.returnConfirmLoanId = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                viewModel.returnConfirmLoanId = nil
            }
            Button("Return", role: .destructive) {
                if let loanId = viewModel.returnConfirmLoanId {
                    viewModel.returnBook(loanId: loanId)
                }
            }
        } message: {
            Text("You will no longer be able to read this book. This action cannot be undone.")
        }
    }

    // MARK: - Snackbar

    private func snackbar(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom))
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(2))
                viewModel.consumeMessage()
            }
        }
    }
}

// MARK: - Borrowed Book Card

private struct BorrowedBookCard: View {
    let loan: LoanInfo
    let onRead: () -> Void
    let onReturn: () -> Void
    let onRenew: () -> Void

    private var display: LoanDisplay { loan.toDisplay() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                BookCoverView(url: loan.coverUrl, width: nil, height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture(perform: onRead)

                if !loan.isTerminal {
                    DueDateBadge(label: display.dueLabel, urgency: display.urgency)
                        .padding(6)
                }
            }

            Text(loan.title ?? "Unknown")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let author = loan.authorName {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !loan.isTerminal, let renewalLabel = display.renewalLabel {
                Text(renewalLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Actions
            if loan.isTerminal {
                Text(loan.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Button("Read", action: onRead)
                        .font(.caption2)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.inkPrimary)

                    Menu {
                        if loan.canRenew {
                            Button("Renew", action: onRenew)
                        }
                        Button("Return", role: .destructive, action: onReturn)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body)
                    }
                }
            }
        }
    }
}

private struct DueDateBadge: View {
    let label: String
    let urgency: LoanUrgency

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(urgency.foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(urgency.backgroundColor)
            .clipShape(Capsule())
    }
}

// MARK: - Library Route

enum LibraryRoute: Hashable {
    case lendingCatalog
}
