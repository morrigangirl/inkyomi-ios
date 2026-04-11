import Foundation

struct CartItem: Identifiable, Equatable, Sendable {
    let bookId: String
    let title: String
    let authorName: String?
    let coverUrl: String?
    let priceUsd: Double

    var id: String { bookId }
}

struct CheckoutConfig: Equatable, Sendable {
    let mode: CheckoutMode
    let liveReady: Bool
}

enum CheckoutMode: String, Codable, Sendable {
    case mock
    case live
}
