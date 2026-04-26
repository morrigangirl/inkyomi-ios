import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SearchBarView(
                    query: viewModel.searchQuery,
                    onQueryChanged: { viewModel.onSearchQueryChanged($0) },
                    onClear: { viewModel.clearSearch() }
                )
                .padding(.horizontal)
                .padding(.bottom, 8)

                if viewModel.searchResults != nil {
                    searchResultsSection
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let landingPage = viewModel.landingPage {
                    landingPageContent(landingPage)
                } else if let error = viewModel.error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle("InkYomi")
        .task {
            viewModel.configure(catalogRepository: container.catalogRepository, libraryRepository: container.libraryRepository, modelContext: modelContext)
            await viewModel.loadLandingPage()
        }
    }

    @ViewBuilder
    private func landingPageContent(_ page: LandingPage) -> some View {
        VStack(spacing: 24) {
            // Hero carousel
            if !page.heroSlides.isEmpty {
                HeroCarouselView(slides: page.heroSlides)
            }

            // Continue reading
            if !viewModel.continueReading.isEmpty {
                continueReadingSection
            }

            // Shelves
            ForEach(page.shelves) { shelf in
                ShelfRowView(shelf: shelf)
            }
        }
    }

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Reading")
                .font(.inkHeadline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.continueReading) { item in
                        NavigationLink(value: item.bookId) {
                            VStack(alignment: .leading, spacing: 4) {
                                BookCoverView(url: item.coverUrl, width: 100, height: 150)
                                Text(item.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                ProgressView(value: Double(item.progressPercent))
                                    .tint(Color.inkPrimary)
                            }
                            .frame(width: 100)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(spacing: 8) {
            if viewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let results = viewModel.searchResults, results.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            } else if let results = viewModel.searchResults {
                LazyVStack(spacing: 12) {
                    ForEach(results) { book in
                        NavigationLink(value: book.id) {
                            BookCardView(book: book)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
