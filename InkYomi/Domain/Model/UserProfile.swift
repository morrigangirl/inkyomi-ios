import Foundation

struct UserProfile: Equatable, Codable, Sendable {
    let id: String
    let email: String
    let displayName: String?
}
