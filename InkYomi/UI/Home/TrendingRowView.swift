import SwiftUI

/// Top-line popularity-ranked feed (`/api/data/books/trending`). Phase 1
/// of the discovery revamp. Renders one horizontal row of book cards
/// above the Featured shelves.
struct TrendingRowView: View {
    let books: [TrendingBook]
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        let coverWidth = CoverSize.shelf.width(for: hSizeClass)
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending now")
                .font(.inkHeadline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(books) { trending in
                        NavigationLink(value: trending.book.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                BookCoverView(
                                    url: trending.book.coverUrl,
                                    width: coverWidth,
                                    height: CoverSize.shelf.height(for: hSizeClass)
                                )
                                Text(trending.book.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                if let author = trending.book.authorName {
                                    Text(author)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: coverWidth)
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
