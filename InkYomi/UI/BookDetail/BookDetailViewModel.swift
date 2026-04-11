import Foundation
import Observation

@MainActor @Observable
final class BookDetailViewModel {
    var bookDetail: BookDetail?
    var isLoading = false
    var error: String?

    private var catalogRepository: (any CatalogRepository)?

    func configure(catalogRepository: any CatalogRepository) {
        self.catalogRepository = catalogRepository
    }

    func loadBook(idOrSlug: String) async {
        guard let catalogRepository else { return }
        isLoading = true
        error = nil
        do {
            bookDetail = try await catalogRepository.getBookDetail(idOrSlug: idOrSlug)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
