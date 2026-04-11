import Foundation

struct CartResponse: Decodable {
    let items: [CartItemDto]
}

struct CartItemDto: Decodable {
    let bookId: String
    let title: String
    let authorName: String?
    let coverUrl: String?
    let priceUsd: String

    func toDomain() -> CartItem {
        CartItem(
            bookId: bookId,
            title: title,
            authorName: authorName,
            coverUrl: coverUrl,
            priceUsd: Double(priceUsd) ?? 0
        )
    }
}

struct AddToCartRequest: Encodable {
    let bookId: String
}

struct CheckoutConfigResponse: Decodable {
    let mode: String
    let liveReady: Bool?

    func toDomain() -> CheckoutConfig {
        CheckoutConfig(
            mode: CheckoutMode(rawValue: mode) ?? .mock,
            liveReady: liveReady ?? false
        )
    }
}

struct CheckoutSessionResponse: Decodable {
    let orderId: String?
    let checkoutUrl: String?
}

struct MockCheckoutResponse: Decodable {
    let orderId: String?
    let itemCount: Int?
    let total: Double?
}
