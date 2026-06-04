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
    /// Backend `preorder_state` ("open" | "paused" | "release_pending" |
    /// "released" | "disabled" | "suspended_by_admin" | "canceled"). nil on
    /// older backends that predate pre-orders.
    let preorderState: String?
    /// ISO-8601 release timestamp for a pre-order; nil when not a pre-order.
    let releaseAt: String?
    let isNewRelease: Bool
    let ratingAvg: Double?
    let ratingCount: Int?
    let owned: Bool
    let authors: [Author]
    let tags: [Tag]
    let categories: [Category]
    /// Pre-purchase "Look Inside" availability for this book.
    let lookInside: LookInside

    /// Storefront pre-order CTA gate — mirrors the web SPA: a committed,
    /// still-unreleased pre-order is published with `preorderState == "open"`
    /// (and `isPurchasable` stays false until it releases). The book-detail
    /// "View Online" button surfaces for these so the reader can complete the
    /// pre-order on inkcolors.shop (commerce is web-only).
    var isPreorderable: Bool { preorderState == "open" }
}

struct Author: Equatable, Sendable, Hashable {
    let id: String
    let name: String
}

/// "Look Inside" status for a book. The reader UI shows the preview entry
/// point only when `available` is true.
struct LookInside: Equatable, Sendable {
    let enabled: Bool
    let available: Bool

    static let unavailable = LookInside(enabled: false, available: false)
}

/// A fetched, server-sanitized HTML excerpt for the pre-purchase preview.
struct LookInsidePreview: Equatable, Sendable {
    let sourceTitle: String?
    /// Sanitized HTML — render in a JavaScript-disabled web view only.
    let previewHtml: String
    let wordCount: Int?
    let truncated: Bool
}
