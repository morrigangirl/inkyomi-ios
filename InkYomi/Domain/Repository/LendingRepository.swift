import Foundation

protocol LendingRepository: Sendable {
    func isLendingEnabled() async -> Bool
    func getCatalog(query: String?) async throws -> OpdsFeed
    func borrowBook(bookId: String) async throws
    func returnBook(loanId: String) async throws
    func renewBook(loanId: String) async throws
    func getActiveLoans() async throws -> [LoanInfo]
    func syncShelf() async throws
    func checkLoanStatus(loanId: String) async throws -> LoanInfo
    func getLoanForBook(bookId: String) async throws -> LoanInfo?
}
