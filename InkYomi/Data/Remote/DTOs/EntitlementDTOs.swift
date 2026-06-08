import Foundation

struct EntitlementBooksResponse: Decodable {
    let books: [EntitlementBookDto]
}

struct EntitlementBookDto: Decodable {
    let id: String
    let title: String
    let slug: String?
    let authorName: String?
    let coverUrl: String?
    // Raw storage paths for the smaller cover renditions (snake_case
    // `cover_card_path` / `cover_thumb_path` on the wire). The owned grid
    // renders at card size, so prefer these over the full-size `coverUrl`
    // — the server emits the bare object path, which must be wrapped in
    // `/api/covers/<path>` like the backend's `getPublicCoverVariantUrl`.
    let coverCardPath: String?
    let coverThumbPath: String?
    let priceUsd: String?

    /// Wraps a raw cover object path in the `/api/covers/` proxy route,
    /// leaving already-absolute URLs untouched. Mirrors the backend
    /// `getPublicCoverVariantUrl` resolver; `BookCoverView` then prepends
    /// the host to the origin-relative result.
    private static func coverPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") { return path }
        return "/api/covers/\(path)"
    }

    func toDomain() -> LibraryBook {
        LibraryBook(
            id: id,
            title: title,
            slug: slug,
            authorName: authorName,
            // Prefer card → thumb → full so the grid fetches the smaller
            // rendition; falls back to the full `coverUrl` when neither
            // variant path is present.
            coverUrl: Self.coverPath(coverCardPath)
                ?? Self.coverPath(coverThumbPath)
                ?? coverUrl,
            priceUsd: priceUsd.flatMap { Double($0) },
            entitlementType: .owned,
            loanInfo: nil
        )
    }
}
