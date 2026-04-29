import SwiftUI

/// Phase 2 of the discovery revamp: full-screen results grid with
/// faceted filters, sort, pagination, and active-filter chip strip.
struct SearchResultsView: View {
    let initialQuery: String?
    let prefilledTagType: TagType?
    let prefilledTagSlug: String?
    let authorId: String?
    let seriesId: String?

    @State private var viewModel = SearchResultsViewModel()
    @Environment(DependencyContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var showFilters = false
    @State private var showSortMenu = false

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
        .navigationTitle(viewModel.query.isEmpty ? "Browse" : viewModel.query)
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
                }
            )
            .presentationDetents([.medium, .large])
        }
        .task {
            viewModel.configure(repository: container.searchRepository)
            await viewModel.initialize(
                query: initialQuery,
                prefilledTagType: prefilledTagType,
                prefilledTagSlug: prefilledTagSlug,
                authorId: authorId,
                seriesId: seriesId
            )
        }
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
            BookCoverView(
                url: book.coverCardUrl ?? book.coverUrl ?? book.coverThumbUrl,
                width: nil,
                height: 210
            )
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
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
    let onToggleTag: (TagType, String) -> Void
    let onPriceRangeChange: (Double?, Double?) -> Void
    let onRatingChange: (Double?) -> Void
    let onClear: () -> Void
    let onApply: () -> Void

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
