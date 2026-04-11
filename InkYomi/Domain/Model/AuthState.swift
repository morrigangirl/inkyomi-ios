import Foundation

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated(UserProfile)
}
