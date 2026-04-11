import Foundation

struct BookDetail: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let slug: String
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
    let tags: [String]
    let categories: [Category]
}

struct Author: Equatable, Sendable {
    let id: String
    let name: String
}
