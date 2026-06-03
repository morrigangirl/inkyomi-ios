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

    // MARK: Look Inside

    /// The fetched preview, once loaded. Nil until the user opens it.
    var lookInsidePreview: LookInsidePreview?
    var isLoadingLookInside = false
    /// True after a fetch that found no preview (HTTP 404) or failed, so
    /// the sheet can show a "no preview" message instead of spinning.
    var lookInsideUnavailable = false

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

    /// Fetch the Look Inside preview on demand (when the user opens it).
    /// A 404 from the backend maps to `lookInsideUnavailable` rather than
    /// an error. Skips the network call if the preview is already loaded.
    func loadLookInside(idOrSlug: String) async {
        guard let catalogRepository else { return }
        guard lookInsidePreview == nil else { return }
        isLoadingLookInside = true
        lookInsideUnavailable = false
        do {
            if let preview = try await catalogRepository.getLookInside(idOrSlug: idOrSlug) {
                lookInsidePreview = preview
            } else {
                lookInsideUnavailable = true
            }
        } catch {
            lookInsideUnavailable = true
        }
        isLoadingLookInside = false
    }
}
