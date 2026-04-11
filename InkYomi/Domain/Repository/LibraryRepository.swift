import Foundation

protocol LibraryRepository: Sendable {
    func getOwnedBooks() async throws -> [LibraryBook]
    func getBorrowedBooks() async throws -> [LibraryBook]
}
