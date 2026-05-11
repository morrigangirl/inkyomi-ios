import SwiftUI

/// Phase 2 of the discovery revamp: full-screen results grid with
/// faceted filters, sort, pagination, and active-filter chip strip.
struct SearchResultsView: View {
    let initialQuery: String?
    let prefilledTagType: TagType?
    let prefilledTagSlug: String?
    /// Pre-applied multi-axis filter — used by Browse Hub "Browse Views"
    /// tiles whose server-resolved category collapses to slugs across
    /// multiple tag types. Mutually exclusive with the single-axis
    /// `prefilledTagType`+`prefilledTagSlug` path.
    let prefilledTagFilters: [TagType: [String]]?
    /// Optional screen title override (used when there's no free-text
    /// query to display, e.g. a Browse Views tile).
    let titleOverride: String?
    let authorId: String?
    let seriesId: String?
    let savedSearchId: String?

    init(
        initialQuery: String? = nil,
        prefilledTagType: TagType? = nil,
        prefilledTagSlug: String? = nil,
        prefilledTagFilters: [TagType: [String]]? = nil,
        titleOverride: String? = nil,
        authorId: String? = nil,
        seriesId: String? = nil,
        savedSearchId: String? = nil
    ) {
        self.initialQuery = initialQuery
        self.prefilledTagType = prefilledTagType
        self.prefilledTagSlug = prefilledTagSlug
        self.prefilledTagFilters = prefilledTagFilters
        self.titleOverride = titleOverride
        self.authorId = authorId
        self.seriesId = seriesId
        self.savedSearchId = savedSearchId
    }

    @State private var viewModel = SearchResultsViewModel()
    @Environment(DependencyContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var showFilters = false
    @State private var showSortMenu = false
    @State private var showSaveDialog = false
    @State private var saveDialogName = ""

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.filters.activeCount > 0 {
                ActiveFiltersStrip(
                    filters: viewModel.filters,
                    facets: viewModel.facets,
                    onRemoveTag: { type, slug in
                        Task { await viewModel.removeTagFilter(type: type, slug: slug) }
                    },
                    onRemoveAuthor: { Task { await viewModel.removeAuthor() } },
                    onRemoveSeries: { Task { await viewModel.removeSeries() } },
                    onRemovePriceRange: { Task { await viewModel.removePriceRange() } },
                    onRemoveRating: { Task { await viewModel.removeRating() } },
                    onClearAll: { Task { await viewModel.clearFilters() } }
                )
            }
            content
        }
        .navigationTitle(resolvedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SearchSortOrder.allCases, id: \.self) { option in
                        Button(option.label) {
                            Task { await viewModel.setSort(option) }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    if viewModel.filters.activeCount > 0 {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    } else {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            FiltersSheet(
                facets: viewModel.facets,
                filters: viewModel.filters,
                canSave: viewModel.filters.activeCount > 0 || !viewModel.query.isEmpty,
                onToggleTag: { type, slug in
                    viewModel.toggleTagFilter(type: type, slug: slug)
                },
                onPriceRangeChange: { lo, hi in
                    viewModel.setPriceRange(lo, hi)
                },
                onRatingChange: { value in
                    viewModel.setRatingMin(value)
                },
                onClear: {
                    Task {
                        await viewModel.clearFilters()
                        showFilters = false
                    }
                },
                onApply: {
                    Task {
                        await viewModel.applyFilters()
                        showFilters = false
                    }
                },
                onSave: {
                    showFilters = false
                    saveDialogName = defaultSaveName
                    showSaveDialog = true
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Save this search", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveDialogName)
            Button("Save") {
                let trimmed = saveDialogName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    Task { await viewModel.saveCurrentSearch(name: trimmed) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            viewModel.configure(
                repository: container.searchRepository,
                savedSearchesRepository: container.savedSearchesRepository
            )
            await viewModel.initialize(
                query: initialQuery,
                prefilledTagType: prefilledTagType,
                prefilledTagSlug: prefilledTagSlug,
                prefilledTagFilters: prefilledTagFilters,
                authorId: authorId,
                seriesId: seriesId,
                savedSearchId: savedSearchId
            )
        }
    }

    /// Title shown in the nav bar. When the caller passes an explicit
    /// title (Browse Views tile), use it; otherwise fall through to the
    /// live query or the generic "Browse" placeholder.
    private var resolvedTitle: String {
        if let titleOverride, !titleOverride.isEmpty { return titleOverride }
        return viewModel.query.isEmpty ? "Browse" : viewModel.query
    }

    /// Default name to pre-fill in the Save dialog: prefer the live
    /// query, then a comma-joined list of selected tag slugs, otherwise
    /// a generic placeholder the user can edit.
    private var defaultSaveName: String {
        let trimmedQuery = viewModel.query.trimmingCharacters(in: .whitespaces)
        if !trimmedQuery.isEmpty { return trimmedQuery }
        let slugs = viewModel.filters.tagSlugs.values.flatMap { $0 }
        if !slugs.isEmpty { return slugs.joined(separator: ", ") }
        return "Untitled search"
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.books.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.books.isEmpty {
            VStack(spacing: 8) {
                ContentUnavailableView("Couldn't load results", systemImage: "exclamationmark.triangle", description: Text(error))
                Button("Retry") { Task { await viewModel.applyFilters() } }
            }
        } else if viewModel.books.isEmpty {
            VStack(spacing: 8) {
                ContentUnavailableView.search
                if let suggest = viewModel.spellSuggest {
                    Button("Did you mean “\(suggest)”?") {
                        Task { await viewModel.setQuery(suggest) }
                    }
                }
                if viewModel.filters.activeCount > 0 {
                    Button("Clear filters") {
                        Task { await viewModel.clearFilters() }
                    }
                }
            }
        } else {
            resultsGrid
        }
    }

    private var resultsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
        return ScrollView {
            VStack(spacing: 0) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(viewModel.books.enumerated()), id: \.element.id) { index, book in
                        NavigationLink(value: book.id) {
                            ResultCard(book: book)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // Trigger loadMore when the user scrolls within
                            // ~6 items of the end of the loaded list.
                            if index >= viewModel.books.count - 6 {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }
}

private struct ResultCard: View {
    let book: SearchResultBook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cover fills the column width and respects the 2:3 spine
            // ratio. `BookCoverView` is built around fixed dimensions
            // (used by horizontal shelves), so for the grid case we use
            // a `GridCoverImage` wrapper that grows to the proposed width.
            GridCoverImage(url: book.coverCardUrl ?? book.coverUrl ?? book.coverThumbUrl)
            Text(book.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
            if let author = book.authorName {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let price = book.priceUsd {
                Text(String(format: "$%.2f", price))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.inkPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Cover wrapper for grid cells: fills the proposed width and clips to
/// a 2:3 aspect ratio. Mirrors `BookCoverView`'s look (rounded corners,
/// soft shadow, on-failure placeholder) but does not require an explicit
/// width/height up-front.
private struct GridCoverImage: View {
    let url: String?

    private var resolvedURL: URL? {
        guard let urlString = url, !urlString.isEmpty else { return nil }
        if let absolute = URL(string: urlString), absolute.scheme != nil {
            return absolute
        }
        return URL(string: urlString, relativeTo: URL(string: "https://inkcolors.shop"))
    }

    var body: some View {
        Group {
            if let imageUrl = resolvedURL {
                CachedAsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        placeholder.overlay(ProgressView())
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.inkPrimary.opacity(0.1))
            .overlay {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color.inkPrimary.opacity(0.3))
            }
    }
}

// MARK: - Active filter strip

private struct ActiveFiltersStrip: View {
    let filters: SearchFilters
    let facets: [FacetGroup]
    let onRemoveTag: (TagType, String) -> Void
    let onRemoveAuthor: () -> Void
    let onRemoveSeries: () -> Void
    let onRemovePriceRange: () -> Void
    let onRemoveRating: () -> Void
    let onClearAll: () -> Void

    private var labelLookup: [String: String] {
        var m: [String: String] = [:]
        for group in facets {
            for item in group.items {
                m["\(group.key)|\(item.value)"] = item.label
            }
        }
        return m
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters.tagSlugs.keys.sorted(by: { $0.wire < $1.wire }), id: \.self) { type in
                    ForEach(filters.tagSlugs[type] ?? [], id: \.self) { slug in
                        let label = labelLookup["\(type.wire)|\(slug)"] ?? slug
                        FilterChipView(label: label) { onRemoveTag(type, slug) }
                    }
                }
                if filters.authorId != nil {
                    FilterChipView(label: "Author", action: onRemoveAuthor)
                }
                if filters.seriesId != nil {
                    FilterChipView(label: "Series", action: onRemoveSeries)
                }
                if filters.priceMin != nil || filters.priceMax != nil {
                    let lo = filters.priceMin.map { String(format: "$%.0f", $0) } ?? "Any"
                    let hi = filters.priceMax.map { String(format: "$%.0f", $0) } ?? "Any"
                    FilterChipView(label: "\(lo)–\(hi)", action: onRemovePriceRange)
                }
                if let rating = filters.ratingMin {
                    FilterChipView(label: String(format: "%.1f★+", rating), action: onRemoveRating)
                }
                if filters.activeCount > 1 {
                    Button("Clear all", role: .destructive, action: onClearAll)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

private struct FilterChipView: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.inkPrimary.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filters bottom sheet

private struct FiltersSheet: View {
    let facets: [FacetGroup]
    let filters: SearchFilters
    let canSave: Bool
    let onToggleTag: (TagType, String) -> Void
    let onPriceRangeChange: (Double?, Double?) -> Void
    let onRatingChange: (Double?) -> Void
    let onClear: () -> Void
    let onApply: () -> Void
    let onSave: () -> Void

    @State private var priceLo: Double = 0
    @State private var priceHi: Double = priceMaxUsd
    @State private var rating: Double = 0
    private static let priceMaxUsd: Double = 50

    private static var priceMaxUsdValue: Double { 50 }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(facets) { group in
                    if let type = TagType.fromWire(group.key), !group.items.isEmpty {
                        Section(group.label) {
                            FacetChipGrid(
                                items: group.items,
                                selectedSlugs: Set(filters.tagSlugs[type] ?? []),
                                onToggle: { slug in onToggleTag(type, slug) }
                            )
                        }
                    }
                }

                Section("Price") {
                    VStack {
                        // Two-thumb price range using paired sliders.
                        HStack {
                            Text(String(format: "$%.0f", priceLo))
                            Spacer()
                            Text(priceHi >= Self.priceMaxUsd - 0.01
                                 ? String(format: "$%.0f+", Self.priceMaxUsd)
                                 : String(format: "$%.0f", priceHi))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Slider(value: $priceLo, in: 0...Self.priceMaxUsd, step: 1) {
                            Text("Min price")
                        }
                        Slider(value: $priceHi, in: 0...Self.priceMaxUsd, step: 1) {
                            Text("Max price")
                        }
                    }
                    .onChange(of: priceLo) { _, _ in
                        if priceLo > priceHi { priceLo = priceHi }
                    }
                    .onChange(of: priceHi) { _, _ in
                        if priceHi < priceLo { priceHi = priceLo }
                    }
                }

                Section("Minimum rating") {
                    VStack(alignment: .leading) {
                        Text(rating < 0.05 ? "Any rating" : String(format: "%.1f stars or more", rating))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $rating, in: 0...5, step: 0.5)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear all", role: .destructive, action: onClear)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if canSave {
                        Button(action: onSave) {
                            Image(systemName: "bookmark")
                                .accessibilityLabel("Save this search")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        // Commit price/rating to filters before applying.
                        let lo: Double? = priceLo > 0.01 ? priceLo : nil
                        let hi: Double? = priceHi < Self.priceMaxUsd - 0.01 ? priceHi : nil
                        onPriceRangeChange(lo, hi)
                        onRatingChange(rating > 0.05 ? rating : nil)
                        onApply()
                    }
                }
            }
            .onAppear {
                priceLo = filters.priceMin ?? 0
                priceHi = filters.priceMax ?? Self.priceMaxUsd
                rating = filters.ratingMin ?? 0
            }
        }
    }
}

private struct FacetChipGrid: View {
    let items: [FacetItem]
    let selectedSlugs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        // Use `LazyVGrid` of flexible columns to flow chips like a chip cloud.
        let columns = [GridItem(.adaptive(minimum: 120), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                let isSelected = selectedSlugs.contains(item.value)
                Button { onToggle(item.value) } label: {
                    HStack(spacing: 4) {
                        Text("\(item.label) (\(item.count))")
                            .font(.caption)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isSelected ? Color.inkPrimary.opacity(0.25) : Color(.systemGray6))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
