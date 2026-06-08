import SwiftUI

struct BookCardView: View {
    let book: Book
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(
                url: book.coverUrl,
                width: CoverSize.thumb.width(for: hSizeClass),
                height: CoverSize.thumb.height(for: hSizeClass)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let author = book.authorName {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let hook = book.hook {
                    Text(hook.htmlStripped())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let chips = book.chips, !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips.prefix(3), id: \.self) { chip in
                            Text(chip)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.inkPrimary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
