import Foundation

// MARK: - OPDS 2.0 Feed Models

struct OpdsFeed: Decodable, Sendable {
    let metadata: OpdsFeedMetadata
    let links: [OpdsLink]?
    let publications: [OpdsPublication]?
    let navigation: [OpdsLink]?
}

struct OpdsFeedMetadata: Decodable, Sendable {
    let title: String
    let numberOfItems: Int?
    let itemsPerPage: Int?
    let currentPage: Int?
    let modified: String?
}

struct OpdsPublication: Decodable, Identifiable {
    let metadata: OpdsPublicationMetadata
    let links: [OpdsLink]?
    let images: [OpdsLink]?

    var id: String {
        // Use self link's bookId extraction, fall back to identifier or title
        extractBookId ?? metadata.identifier ?? metadata.title
    }

    /// Extract the book UUID from the publication's self link.
    /// The self link href is like `.../api/opds/publications/{uuid}`.
    var extractBookId: String? {
        links?.first { $0.rel == "self" }?.href
            .components(separatedBy: "/publications/").last?
            .components(separatedBy: "?").first
    }
}

struct OpdsPublicationMetadata: Decodable, Sendable {
    let type: String?
    let title: String
    let identifier: String?
    let author: [OpdsContributor]?
    let language: [String]?
    let published: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case title, identifier, author, language, published, description
    }
}

struct OpdsContributor: Decodable, Sendable {
    let name: String
}

struct OpdsLink: Decodable, Sendable {
    let rel: String?
    let href: String
    let type: String?
    let templated: Bool?
    let title: String?
    let properties: OpdsLinkProperties?
}

struct OpdsLinkProperties: Decodable, Sendable {
    let availability: OpdsAvailability?
    let indirectAcquisition: [OpdsIndirectAcquisition]?
    let price: OpdsPrice?
    let lcpHashedPassphrase: String?

    enum CodingKeys: String, CodingKey {
        case availability
        case indirectAcquisition = "indirect_acquisition"
        case price
        case lcpHashedPassphrase = "lcp_hashed_passphrase"
    }
}

struct OpdsAvailability: Decodable, Sendable {
    let state: String
    let since: String?
    let until: String?
}

struct OpdsIndirectAcquisition: Decodable, Sendable {
    let type: String
    let child: [OpdsIndirectAcquisition]?
}

struct OpdsPrice: Decodable, Sendable {
    let currency: String
    let value: Double
}
