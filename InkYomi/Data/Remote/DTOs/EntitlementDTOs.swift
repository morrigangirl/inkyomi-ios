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
    let priceUsd: String?

    func toDomain() -> LibraryBook {
        LibraryBook(
            id: id,
            title: title,
            slug: slug,
            authorName: authorName,
            coverUrl: coverUrl,
            priceUsd: priceUsd.flatMap { Double($0) },
            entitlementType: .owned,
            loanInfo: nil
        )
    }
}
