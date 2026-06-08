import SwiftUI

/// Phase 1 of the discovery revamp: vertical stack of section headers,
/// each with a 2-column grid of "discovery tiles" pulled from
/// `/api/data/categories/browse-hub`. Each tile shows a 3-cover montage,
/// the label, and the book count. Taps route to a `SearchResultsView`
/// pre-filtered by the corresponding tag (Phase 2).
struct BrowseHubSection: View {
    let groups: [BrowseHubGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Browse the catalog")
                .font(.inkHeadline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal)

            ForEach(groups) { group in
                BrowseHubGroupView(group: group)
            }
        }
    }
}

private struct BrowseHubGroupView: View {
    let group: BrowseHubGroup

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.tiles) { tile in
                    if let route = tile.searchRoute(for: group.key) {
                        NavigationLink(value: route) {
                            BrowseHubTileCard(tile: tile)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // by-series, by-character, featured groups don't
                        // map to tag-type filters yet (need entity-based
                        // search support). Render the tile but make it
                        // inert so it stays visually consistent.
                        BrowseHubTileCard(tile: tile)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Single discovery tile — 3-cover overlapping montage on top, label and
/// book count underneath.
struct BrowseHubTileCard: View {
    let tile: BrowseHubTile

    private var displayCovers: [String] {
        Array(tile.coverMontageUrls.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.inkPrimary.opacity(0.08))

                if displayCovers.isEmpty {
                    Image(systemName: tileSystemImage)
                        .font(.title)
                        .foregroundStyle(Color.inkPrimary.opacity(0.4))
                } else {
                    coverMontage
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(tile.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(tile.bookCount) book\(tile.bookCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Three covers fanned at slight rotations. Mirrors the Android
    /// `BrowseHubTileCard` cover-montage style.
    private var coverMontage: some View {
        GeometryReader { geo in
            let coverHeight = geo.size.height * 0.85
            let coverWidth = coverHeight * (2.0 / 3.0)
            let centerX = geo.size.width / 2
            let baseY = geo.size.height / 2

            ZStack {
                ForEach(Array(displayCovers.enumerated()), id: \.offset) { index, url in
                    let layout = montageLayout(for: index, total: displayCovers.count)
                    BookCoverView(
                        url: url,
                        width: coverWidth,
                        height: coverHeight
                    )
                    .position(x: centerX + layout.dx, y: baseY)
                    .rotationEffect(.degrees(layout.rotation))
                }
            }
        }
    }

    private func montageLayout(for index: Int, total: Int) -> (dx: CGFloat, rotation: Double) {
        // Indexes ordered so the centre cover is drawn last (on top).
        // Pattern: left, right, centre.
        switch (index, total) {
        case (0, 3): return (dx: -28, rotation: -10)
        case (1, 3): return (dx: 28, rotation: 10)
        case (2, 3): return (dx: 0, rotation: 0)
        case (0, 2): return (dx: -16, rotation: -8)
        case (1, 2): return (dx: 16, rotation: 8)
        default:     return (dx: 0, rotation: 0)
        }
    }

    private var tileSystemImage: String {
        switch tile.icon {
        case "book": "book.fill"
        case "tag": "tag.fill"
        case "heart": "heart.fill"
        default: "book.closed.fill"
        }
    }
}

private extension BrowseHubTile {
    /// Map the `(groupKey, tileKey)` pair to a Phase 2 search route. The
    /// group key indicates which tag-type axis ("by-genre" → `.genre`,
    /// "by-mood" → `.tone`, etc.) and the tile key is the slug.
    func searchRoute(for groupKey: String) -> SearchRoute? {
        let type: TagType?
        switch groupKey {
        case "by-genre":     type = .genre
        case "by-subgenre":  type = .subgenre
        case "by-mood":      type = .tone
        case "by-trope":     type = .trope
        case "by-identity":  type = .identity
        case "by-outcome":   type = .outcome
        case "by-content":   type = .contentFlag
        default:             type = nil
        }
        guard let type else { return nil }
        return .results(tagType: type, tagSlug: key)
    }
}
