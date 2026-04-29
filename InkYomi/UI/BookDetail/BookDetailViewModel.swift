import Foundation
import Observation

@MainActor @Observable
final class BookDetailViewModel {
    var bookDetail: BookDetail?
    var isLoading = false
    var error: String?

    /// "More like this" rail. Fetched in parallel with the book detail
    /// once `book.icin` is known. Failure is silent — the rail simply
    /// doesn't render.
    var relatedBooks: [RelatedBook] = []

    private var catalogRepository: (any CatalogRepository)?
    private var discoveryRepository: (any DiscoveryRepository)?

    func configure(
        catalogRepository: any CatalogRepository,
        discoveryRepository: any DiscoveryRepository
    ) {
        self.catalogRepository = catalogRepository
        self.discoveryRepository = discoveryRepository
    }

    func loadBook(idOrSlug: String) async {
        guard let catalogRepository else { return }
        isLoading = true
        error = nil
        do {
            let book = try await catalogRepository.getBookDetail(idOrSlug: idOrSlug)
            bookDetail = book
            isLoading = false
            // Related-books fetch needs the seed `icin` (URL parameter
            // on the backend route), not the UUID. Failure is silent —
            // the rail just doesn't render.
            if let icin = book.icin {
                await loadRelated(icin: icin)
            }
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    private func loadRelated(icin: String) async {
        guard let discoveryRepository else { return }
        do {
            relatedBooks = try await discoveryRepository.getRelated(icin: icin)
        } catch {
            // Soft enhancement — no error surfaced on failure.
        }
    }
}
