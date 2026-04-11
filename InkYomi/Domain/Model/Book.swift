import Foundation

struct Book: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let slug: String
    let coverUrl: String?
    let authorName: String?
    let priceUsd: Double?
    let hook: String?
    let chips: [String]?
    let isNewRelease: Bool
}
