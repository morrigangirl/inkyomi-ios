import Foundation
import SwiftData

actor LendingRepositoryImpl: LendingRepository {
    private let catalogAPI: OpdsCatalogAPIService
    private let api: OpdsLendingAPIService
    private let transportSecretStore: LcpTransportSecretStore
    private let lendingDownloadManager: LendingDownloadManager
    private let modelContainer: ModelContainer

    init(
        catalogAPI: OpdsCatalogAPIService,
        api: OpdsLendingAPIService,
        transportSecretStore: LcpTransportSecretStore,
        lendingDownloadManager: LendingDownloadManager,
        modelContainer: ModelContainer
    ) {
        self.catalogAPI = catalogAPI
        self.api = api
        self.transportSecretStore = transportSecretStore
        self.lendingDownloadManager = lendingDownloadManager
        self.modelContainer = modelContainer
    }

    func isLendingEnabled() async -> Bool {
        do {
            _ = try await catalogAPI.getCatalog()
            return true
        } catch {
            return false
        }
    }

    func getCatalog(query: String?) async throws -> OpdsFeed {
        try await catalogAPI.getCatalog(query: query)
    }

    func borrowBook(bookId: String) async throws {
        let response = try await api.borrowBook(bookId: bookId)

        // Extract loanId from status link
        let statusHref = response.license.links.first { $0.rel == "status" }?.href ?? ""
        let loanId = statusHref
            .components(separatedBy: "/licenses/").last?
            .components(separatedBy: "/status").first ?? response.license.id

        // Store transport secret
        try transportSecretStore.storeTransportSecretHex(response.transportSecretHex, loanId: loanId)

        // Cache loan in SwiftData
        let context = ModelContext(modelContainer)
        let loan = LoanCacheModel(
            loanId: loanId,
            licenseId: response.license.id,
            bookId: bookId,
            status: "active",
            borrowedAt: Date()
        )
        context.insert(loan)
        try context.save()
    }

    func returnBook(loanId: String) async throws {
        _ = try await api.returnBook(loanId: loanId)

        // Update local state
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.loanId == loanId }
        )
        if let loan = try context.fetch(descriptor).first {
            loan.status = "returned"
            loan.returnedAt = Date()
            try context.save()
        }

        // Clean up the cached EPUB and decryption material. Without
        // the file delete here the borrowed-books directory would
        // accumulate dead EPUBs forever; without the secret delete
        // the keychain entry would survive even though it's now
        // unusable. Both are best-effort — the local state is
        // already correct.
        lendingDownloadManager.deleteLendingBook(loanId: loanId)
        try? transportSecretStore.deleteTransportSecret(loanId: loanId)
    }

    func renewBook(loanId: String) async throws {
        _ = try await api.renewBook(loanId: loanId)

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.loanId == loanId }
        )
        if let loan = try context.fetch(descriptor).first {
            loan.renewedCount += 1
            loan.status = "active"
            try context.save()
        }
    }

    @MainActor
    func getActiveLoans() async throws -> [LoanInfo] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.status == "active" || $0.status == "ready" }
        )
        let loans = try context.fetch(descriptor)

        // Hydrate with cached book metadata
        return loans.map { loan in
            var info = loan.toLoanInfo()
            // Try to get title/author/cover from CachedBookModel
            let bid = loan.bookId
            let bookDescriptor = FetchDescriptor<CachedBookModel>(
                predicate: #Predicate { $0.bookId == bid }
            )
            if let cached = try? context.fetch(bookDescriptor).first {
                if info.title == nil || info.title?.isEmpty == true {
                    info = LoanInfo(
                        loanId: info.loanId, licenseId: info.licenseId, bookId: info.bookId,
                        title: cached.title.isEmpty ? info.title : cached.title,
                        authorName: cached.authorName ?? info.authorName,
                        coverUrl: cached.coverUrl ?? info.coverUrl,
                        status: info.status, dueAt: info.dueAt,
                        renewedCount: info.renewedCount, maxRenewals: info.maxRenewals
                    )
                }
            }
            return info
        }
    }

    @MainActor
    func getLoanForBook(bookId: String) async throws -> LoanInfo? {
        let context = modelContainer.mainContext
        let bid = bookId
        let descriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.bookId == bid && ($0.status == "active" || $0.status == "ready") }
        )
        return try context.fetch(descriptor).first?.toLoanInfo()
    }

    @MainActor
    func syncShelf() async throws {
        let shelf = try await catalogAPI.getShelf()
        let context = modelContainer.mainContext

        // Track every loanId the server still reports as live so we
        // can reconcile previously-active loans the server has since
        // returned / expired / revoked (the shelf endpoint just
        // stops listing them rather than emitting a tombstone).
        var seenLoanIds: Set<String> = []

        for pub in shelf.publications ?? [] {
            let acquisitionLink = pub.links?.first {
                $0.type == "application/vnd.readium.lcp.license.v1.0+json"
            }
            guard let acquisitionLink else { continue }
            guard let props = acquisitionLink.properties,
                  let availability = props.availability else { continue }

            // Parse loan ID from the license link URL
            let loanId = acquisitionLink.href
                .components(separatedBy: "/licenses/").last?
                .components(separatedBy: ".lcpl").first ?? ""

            guard !loanId.isEmpty else { continue }
            seenLoanIds.insert(loanId)

            // Extract book UUID from cover image href (/api/covers/{uuid}/...)
            let coverHref = pub.images?.first?.href
            let bookIdFromCover: String? = {
                guard let href = coverHref,
                      let afterCovers = href.components(separatedBy: "/api/covers/").last,
                      let uuid = afterCovers.components(separatedBy: "/").first,
                      uuid.count == 36, uuid.contains("-") else { return nil }
                return uuid
            }()

            // Look up existing loan
            let lid = loanId
            let existingDescriptor = FetchDescriptor<LoanCacheModel>(
                predicate: #Predicate { $0.loanId == lid }
            )
            let existing = try? context.fetch(existingDescriptor).first

            guard let bookId = bookIdFromCover ?? existing?.bookId.nilIfEmpty else {
                continue
            }

            // Normalize "available" → "active"
            let normalizedStatus = availability.state == "available" ? "active" : availability.state

            // Parse dates from ISO8601 strings
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let existing {
                existing.bookId = bookId
                existing.status = normalizedStatus
                if let since = availability.since { existing.borrowedAt = formatter.date(from: since) }
                if let until = availability.until { existing.dueAt = formatter.date(from: until) }
            } else {
                let loan = LoanCacheModel(
                    loanId: loanId,
                    licenseId: "",
                    bookId: bookId,
                    status: normalizedStatus,
                    dueAt: availability.until.flatMap { formatter.date(from: $0) },
                    borrowedAt: availability.since.flatMap { formatter.date(from: $0) }
                )
                context.insert(loan)
            }

            // Pre-seed CachedBookModel with metadata from shelf
            let bid = bookId
            let bookDescriptor = FetchDescriptor<CachedBookModel>(
                predicate: #Predicate { $0.bookId == bid }
            )
            let existingBook = try? context.fetch(bookDescriptor).first
            let title = pub.metadata.title
            let authorName = pub.metadata.author?.first?.name
            let coverUrl = resolveUrl(coverHref)

            if existingBook == nil {
                let cached = CachedBookModel(
                    bookId: bookId,
                    title: title,
                    authorName: authorName,
                    coverUrl: coverUrl
                )
                context.insert(cached)
            } else if let book = existingBook,
                      (book.coverUrl == nil || book.title.isEmpty || book.authorName == nil) {
                if book.title.isEmpty { book.title = title }
                if book.authorName == nil { book.authorName = authorName }
                if book.coverUrl == nil { book.coverUrl = coverUrl }
            }
        }

        // Reconcile vanished loans: anything we still think is active
        // that the server didn't include in the shelf is now returned
        // / expired / revoked. Mirror the BookRepository's terminal-
        // loan cleanup so the Library refreshes, cached EPUBs go
        // away, and the keychain transport-secret entry is purged.
        let staleDescriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.status == "active" || $0.status == "ready" }
        )
        if let active = try? context.fetch(staleDescriptor) {
            for loan in active where !seenLoanIds.contains(loan.loanId) {
                let loanId = loan.loanId
                loan.status = "returned"
                if loan.returnedAt == nil { loan.returnedAt = Date() }
                lendingDownloadManager.deleteLendingBook(loanId: loanId)
                try? transportSecretStore.deleteTransportSecret(loanId: loanId)
            }
        }

        try context.save()
    }

    func checkLoanStatus(loanId: String) async throws -> LoanInfo {
        let response = try await api.getLoanStatus(loanId: loanId)

        let context = ModelContext(modelContainer)
        let lid = loanId
        let descriptor = FetchDescriptor<LoanCacheModel>(
            predicate: #Predicate { $0.loanId == lid }
        )
        if let loan = try context.fetch(descriptor).first {
            loan.status = response.status
            try context.save()
            return loan.toLoanInfo()
        }

        return LoanInfo(
            loanId: loanId,
            licenseId: response.id,
            bookId: "",
            status: LoanStatus(rawValue: response.status) ?? .active,
            dueAt: nil,
            renewedCount: 0,
            maxRenewals: Constants.maxLoanRenewals
        )
    }

    private nonisolated func resolveUrl(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        if path.hasPrefix("/") { return "https://inkcolors.shop\(path)" }
        return "https://inkcolors.shop/\(path)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
