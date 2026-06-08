import SwiftUI

struct BookDetailView: View {
    let bookId: String
    @Environment(DependencyContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.openURL) private var openURL
    @State private var viewModel = BookDetailViewModel()
    @State private var showReader = false
    @State private var showLookInside = false

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
        .announcesChanges(of: viewModel.error) { $0 }
        .sheet(isPresented: $showLookInside) {
            LookInsideView(
                idOrSlug: viewModel.bookDetail?.icin ?? bookId,
                bookTitle: viewModel.bookDetail?.title ?? "Preview",
                viewModel: viewModel
            )
        }
        .task {
            viewModel.configure(
                catalogRepository: container.catalogRepository,
                discoveryRepository: container.discoveryRepository
            )
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
                        lookInsideButton(for: book)
                    }
                }
                .padding(.horizontal)

                tagsRow(book)
                descriptionSection(book)
                relatedBooksRow
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
                        lookInsideButton(for: book)
                    }
                    .frame(width: CoverSize.detail.width(for: hSizeClass))

                    VStack(alignment: .leading, spacing: 20) {
                        titleBlock(book)
                        tagsRow(book)
                        descriptionSection(book)
                        relatedBooksRow
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
            if let author = book.authors.first {
                NavigationLink(value: SearchRoute.results(authorId: author.id)) {
                    Text(author.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.inkPrimary)
                }
                .buttonStyle(.plain)
            } else if let authorName = book.authorName {
                Text(authorName)
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
                    ForEach(book.tags) { tag in
                        if let type = tag.tagType {
                            // Phase 3: tag with a known tag_type → tap routes
                            // to filtered SearchResultsView.
                            NavigationLink(value: SearchRoute.results(tagType: type, tagSlug: tag.slug)) {
                                Text(tag.label)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.inkPrimary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Legacy tag without `tag_type` — render as
                            // an inert chip for visual consistency.
                            Text(tag.label)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.inkPrimary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, hSizeClass == .regular ? 0 : 16)
            }
        }
    }

    @ViewBuilder
    private var relatedBooksRow: some View {
        if !viewModel.relatedBooks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("More like this")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, hSizeClass == .regular ? 0 : 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(viewModel.relatedBooks) { related in
                            NavigationLink(value: related.book.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    BookCoverView(
                                        url: related.book.coverCardUrl ?? related.book.coverUrl ?? related.book.coverThumbUrl,
                                        width: 110,
                                        height: 165
                                    )
                                    Text(related.book.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    if let author = related.book.authorName {
                                        Text(author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    if let reason = related.reasons.first {
                                        Text(reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(width: 110)
                                .accessibilityElement(children: .combine)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, hSizeClass == .regular ? 0 : 16)
                }
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
        } else if book.isPurchasable || book.isPreorderable {
            // Purchases happen on the website, never in-app, to avoid
            // in-app-purchase fees. Open the book's public page in the
            // system default browser (external) so the user clearly
            // leaves the app — not an in-app SFSafariViewController. For a
            // pre-order this is where the reader places the reservation.
            Button {
                if let url = URL(string: "https://inkcolors.shop/books/\(book.icin ?? book.slug)") {
                    openURL(url)
                }
            } label: {
                Label(book.isPreorderable ? "Pre-order Online" : "View Online",
                      systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.inkSecondary)
        }
    }

    /// "Look Inside" pre-purchase preview entry point. Shown only when the
    /// backend reports a preview is available for this book.
    @ViewBuilder
    private func lookInsideButton(for book: BookDetail) -> some View {
        if book.lookInside.available {
            Button {
                showLookInside = true
            } label: {
                Label("Look Inside", systemImage: "book.pages")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.inkPrimary)
        }
    }
}
