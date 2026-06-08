import SwiftUI

struct ShelfRowView: View {
    let shelf: Shelf
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        let coverWidth = CoverSize.shelf.width(for: hSizeClass)
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.inkHeadline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelf.books) { book in
                        NavigationLink(value: book.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                BookCoverView(
                                    url: book.coverUrl,
                                    width: coverWidth,
                                    height: CoverSize.shelf.height(for: hSizeClass)
                                )
                                Text(book.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                if let author = book.authorName {
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
