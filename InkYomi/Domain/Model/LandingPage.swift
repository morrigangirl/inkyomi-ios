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
    let book: Book?
}

struct Category: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let slug: String
}
