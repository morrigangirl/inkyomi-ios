import SwiftUI

struct BookDetailView: View {
    let bookId: String
    @Environment(DependencyContainer.self) private var container
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
        ScrollView {
            VStack(spacing: 20) {
                // Cover + metadata header
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(url: book.coverUrl, width: 140, height: 210)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.title)
                            .font(.title3.bold())
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

                        Spacer()

                        actionButton(for: book)
                    }
                }
                .padding(.horizontal)

                // Tags
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
                        .padding(.horizontal)
                    }
                }

                // Description
                if let description = book.fullDescription ?? book.shortDescription {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this book")
                            .font(.headline)
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private func actionButton(for book: BookDetail) -> some View {
        if book.owned {
            Button {
                showReader = true
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
