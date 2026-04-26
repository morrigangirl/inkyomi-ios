import SwiftUI

struct BookDetailView: View {
    let bookId: String
    @Environment(DependencyContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var viewModel = BookDetailViewModel()
    @State private var showReader = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let book = viewModel.bookDetail {
                bookContent(book)
            } else if let error = viewModel.error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .navigationTitle(viewModel.bookDetail?.title ?? "Book")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(catalogRepository: container.catalogRepository)
            await viewModel.loadBook(idOrSlug: bookId)
        }
    }

    @ViewBuilder
    private func bookContent(_ book: BookDetail) -> some View {
        if hSizeClass == .regular {
            regularLayout(book)
        } else {
            compactLayout(book)
        }
    }

    // MARK: - Compact (iPhone) layout

    @ViewBuilder
    private func compactLayout(_ book: BookDetail) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(
                        url: book.coverUrl,
                        width: CoverSize.detail.width(for: hSizeClass),
                        height: CoverSize.detail.height(for: hSizeClass)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        titleBlock(book)
                        Spacer()
                        actionButton(for: book)
                    }
                }
                .padding(.horizontal)

                tagsRow(book)
                descriptionSection(book)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Regular (iPad) layout

    @ViewBuilder
    private func regularLayout(_ book: BookDetail) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 32) {
                    VStack(spacing: 16) {
                        BookCoverView(
                            url: book.coverUrl,
                            width: CoverSize.detail.width(for: hSizeClass),
                            height: CoverSize.detail.height(for: hSizeClass)
                        )
                        actionButton(for: book)
                    }
                    .frame(width: CoverSize.detail.width(for: hSizeClass))

                    VStack(alignment: .leading, spacing: 20) {
                        titleBlock(book)
                        tagsRow(book)
                        descriptionSection(book)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: ContentMaxWidth.reading(for: hSizeClass) ?? .infinity)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Shared sections

    @ViewBuilder
    private func titleBlock(_ book: BookDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(book.title)
                .font(hSizeClass == .regular ? .title.bold() : .title3.bold())
            if let subtitle = book.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let author = book.authorName {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let rating = book.ratingAvg, let count = book.ratingCount {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(String(format: "%.1f", rating))
                        .font(.caption)
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func tagsRow(_ book: BookDetail) -> some View {
        if !book.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(book.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.inkPrimary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, hSizeClass == .regular ? 0 : 16)
            }
        }
    }

    @ViewBuilder
    private func descriptionSection(_ book: BookDetail) -> some View {
        if let description = book.fullDescription ?? book.shortDescription {
            VStack(alignment: .leading, spacing: 8) {
                Text("About this book")
                    .font(.headline)
                HTMLTextView(html: description)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, hSizeClass == .regular ? 0 : 16)
        }
    }

    @ViewBuilder
    private func actionButton(for book: BookDetail) -> some View {
        if book.owned {
            Button {
                Task {
                    await container.bookRepository.cacheBookMetadata(
                        bookId: book.id,
                        title: book.title,
                        authorName: book.authorName,
                        coverUrl: book.coverUrl
                    )
                    showReader = true
                }
            } label: {
                Label("Read", systemImage: "book.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkPrimary)
            .fullScreenCover(isPresented: $showReader) {
                ReaderView(bookId: bookId)
            }
        } else if book.isPurchasable, let price = book.priceUsd {
            Button {
                // Add to cart
            } label: {
                Label(String(format: "Add to Cart - $%.2f", price), systemImage: "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkSecondary)
        }
    }
}
