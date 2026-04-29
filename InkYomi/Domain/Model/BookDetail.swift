import Foundation

struct BookDetail: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let slug: String
    /// Public-facing book identifier — used to key the related-books
    /// endpoint. Optional because not every detail response has been
    /// migrated to surface it.
    let icin: String?
    let hook: String?
    let shortDescription: String?
    let fullDescription: String?
    let authorName: String?
    let coverUrl: String?
    let priceUsd: Double?
    let isPurchasable: Bool
    let isNewRelease: Bool
    let ratingAvg: Double?
    let ratingCount: Int?
    let owned: Bool
    let authors: [Author]
    let tags: [Tag]
    let categories: [Category]
}

struct Author: Equatable, Sendable, Hashable {
    let id: String
    let name: String
}
