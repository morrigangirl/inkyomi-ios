import Foundation
import SwiftData

struct LibraryRepositoryImpl: LibraryRepository, Sendable {
    private let entitlementAPI: EntitlementAPIService
    private let modelContainer: ModelContainer

    init(entitlementAPI: EntitlementAPIService, modelContainer: ModelContainer) {
        self.entitlementAPI = entitlementAPI
        self.modelContainer = modelContainer
    }

    func getOwnedBooks() async throws -> [LibraryBook] {
        let response = try await entitlementAPI.getMyBooks()
        return response.books.map { $0.toDomain() }
    }

    @MainActor
    func getBorrowedBooks() async throws -> [LibraryBook] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.status == "active" || $0.status == "ready" }
        )
        let loans = try context.fetch(descriptor)
        return loans.map { loan in
            LibraryBook(
                id: loan.bookId,
                title: loan.bookTitle ?? "Unknown",
                slug: nil,
                authorName: loan.authorName,
                coverUrl: loan.coverUrl,
                priceUsd: nil,
                entitlementType: .borrowed,
                loanInfo: loan.toLoanInfo()
            )
        }
    }
}
