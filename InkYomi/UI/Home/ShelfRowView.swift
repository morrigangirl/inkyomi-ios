import SwiftUI

struct ShelfRowView: View {
    let shelf: Shelf

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.inkHeadline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelf.books) { book in
                        NavigationLink(value: book.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                BookCoverView(url: book.coverUrl, width: 120, height: 180)
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
                            .frame(width: 120)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
