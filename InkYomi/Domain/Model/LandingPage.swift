import Foundation

struct LandingPage: Equatable, Sendable {
    let shelves: [Shelf]
    let heroSlides: [HeroSlide]
    let categories: [Category]
}

struct Shelf: Identifiable, Equatable, Sendable {
    let id: String
    let slug: String
    let title: String
    let books: [Book]
}

struct HeroSlide: Identifiable, Equatable, Sendable {
    let id: String
    let eyebrow: String?
    let slideType: String?
    let bannerImageUrl: String?
    let bannerSettings: BannerSettings?
    let book: Book?
}

/// Subset of the server's banner_settings JSONB needed for iOS rendering.
/// Mirrors the camelCase keys the server emits inside `banner_settings`.
/// Mobile values take precedence on compact size class; desktop values
/// (focalX/focalY/customZoom) act as fallbacks.
struct BannerSettings: Equatable, Sendable {
    let focalX: Double?
    let focalY: Double?
    let customZoom: Double?
    let mobileFocalX: Double?
    let mobileFocalY: Double?
    let mobileZoom: Double?
    let mobileBannerUrl: String?
    let slideClickable: Bool?

    var isClickable: Bool { slideClickable ?? true }
}

struct Category: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let slug: String
}
