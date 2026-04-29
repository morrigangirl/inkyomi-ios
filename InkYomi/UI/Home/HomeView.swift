import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Tap-to-navigate search bar — opens the Phase 2 typeahead
                // overlay. The legacy inline-search behaviour is gated
                // behind a debug fallback that's no longer wired through.
                NavigationLink(value: SearchRoute.searchOverlay) {
                    SearchBarLink()
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let landingPage = viewModel.landingPage {
                    landingPageContent(landingPage)
                } else if let error = viewModel.error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await viewModel.refresh()
        }
        .background(searchShortcut)
        .navigationTitle("InkYomi")
        .task {
            viewModel.configure(
                catalogRepository: container.catalogRepository,
                discoveryRepository: container.discoveryRepository,
                libraryRepository: container.libraryRepository,
                modelContext: modelContext
            )
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

            // Trending now (Phase 1 — new)
            if !viewModel.trending.isEmpty {
                TrendingRowView(books: viewModel.trending)
            }

            // Shelves
            ForEach(page.shelves) { shelf in
                ShelfRowView(shelf: shelf)
            }

            // Browse the catalog (Phase 1 — new)
            if !viewModel.browseHub.isEmpty {
                BrowseHubSection(groups: viewModel.browseHub)
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
                        let coverWidth = CoverSize.continueRow.width(for: hSizeClass)
                        NavigationLink(value: item.bookId) {
                            VStack(alignment: .leading, spacing: 4) {
                                BookCoverView(
                                    url: item.coverUrl,
                                    width: coverWidth,
                                    height: CoverSize.continueRow.height(for: hSizeClass)
                                )
                                Text(item.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                ProgressView(value: Double(item.progressPercent))
                                    .tint(Color.inkPrimary)
                            }
                            .frame(width: coverWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var searchShortcut: some View {
        Button("Find") {
            NotificationCenter.default.post(name: .focusHomeSearch, object: nil)
        }
        .keyboardShortcut("f", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
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
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Non-editable search-bar look-alike that opens the Phase 2 typeahead
/// overlay when tapped. Dropped from the inline-search path along with
/// the discovery revamp Phase 2.
private struct SearchBarLink: View {
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Search books, authors, tags…")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
