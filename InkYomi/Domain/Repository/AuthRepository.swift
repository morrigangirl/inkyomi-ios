import Foundation

protocol AuthRepository: Sendable {
    func login(email: String, password: String) async throws
    func refresh() async throws
    func forgotPassword(email: String) async throws
    func signOut() async
    func getAccessToken() async -> String?
}
