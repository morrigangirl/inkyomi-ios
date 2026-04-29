import SwiftUI

/// Phase 2 of the discovery revamp: typeahead overlay opened by tapping
/// the Home search bar. Auto-focuses, debounces 250 ms to
/// `/api/search/v2/suggest`, and renders four grouped sections (Books,
/// Authors, Series, Tags) with a "Search for '<query>'" footer that
/// routes to the full results screen.
struct SearchView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SearchViewModel()
    @FocusState private var isFocused: Bool

    /// Dismissal action passed to navigation. We rely on the parent
    /// NavigationStack's `path` for popping.
    let onSubmitQuery: (String) -> Void

    init(onSubmitQuery: @escaping (String) -> Void) {
        self.onSubmitQuery = onSubmitQuery
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search books, authors, tags…", text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.onQueryChanged($0) }
                ))
                .focused($isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { submit(viewModel.query) }
                if !viewModel.query.isEmpty {
                    Button { viewModel.clearQuery() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 8)

            content
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(repository: container.searchRepository, recentSearches: container.recentSearches)
            // Focus on first appearance.
            try? await Task.sleep(nanoseconds: 80_000_000)
            isFocused = true
        }
    }

    private func submit(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.rememberSubmission(trimmed)
        onSubmitQuery(trimmed)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.suggestions == nil {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
            recentsList
        } else if viewModel.suggestions == nil {
            Text("Type at least 2 characters.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
                .frame(maxWidth: .infinity)
        } else if let suggestions = viewModel.suggestions {
            suggestionsList(suggestions)
        }
    }

    @ViewBuilder
    private var recentsList: some View {
        if let store = viewModel.recentSearches, !store.recentQueries.isEmpty {
            List {
                Section {
                    ForEach(store.recentQueries, id: \.self) { q in
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                            Text(q)
                            Spacer()
                            Button(role: .destructive) {
                                store.remove(q)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { submit(q) }
                    }
                } header: {
                    HStack {
                        Text("Recent searches")
                        Spacer()
                        Button("Clear", role: .destructive) {
                            store.clear()
                        }
                        .font(.caption)
                    }
                }
            }
            .listStyle(.plain)
        } else {
            Text("Start typing to search by title, author, series, or tag.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func suggestionsList(_ suggestions: SuggestResults) -> some View {
        let trimmedQuery = viewModel.query.trimmingCharacters(in: .whitespaces)
        List {
            if !suggestions.books.isEmpty {
                Section("Books") {
                    ForEach(suggestions.books) { book in
                        NavigationLink(value: book.id) {
                            BookSuggestionRow(book: book)
                        }
                    }
                }
            }
            if !suggestions.authors.isEmpty {
                Section("Authors") {
                    ForEach(suggestions.authors) { author in
                        NavigationLink(value: SearchRoute.results(authorId: author.id)) {
                            EntityRow(entity: author)
                        }
                    }
                }
            }
            if !suggestions.series.isEmpty {
                Section("Series") {
                    ForEach(suggestions.series) { series in
                        NavigationLink(value: SearchRoute.results(seriesId: series.id)) {
                            EntityRow(entity: series)
                        }
                    }
                }
            }
            if !suggestions.tags.isEmpty {
                Section("Tags") {
                    ForEach(suggestions.tags) { tag in
                        NavigationLink(value: SearchRoute.results(tagType: tag.tagType, tagSlug: tag.slug)) {
                            TagSuggestionRow(tag: tag)
                        }
                    }
                }
            }
            if suggestions.isEmpty {
                Text("No matches yet — try a different query, or tap below to search the full catalog.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
            }
            // "Search for '<query>'" footer always visible.
            Button {
                submit(trimmedQuery)
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search for “\(trimmedQuery)”")
                        .fontWeight(.medium)
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct BookSuggestionRow: View {
    let book: SuggestBook

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(url: book.coverThumbUrl, width: 32, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .lineLimit(2)
                if let author = book.authorName {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct EntityRow: View {
    let entity: SuggestEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entity.label)
            if let count = entity.bookCount {
                Text(count == 1 ? "1 book" : "\(count) books")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TagSuggestionRow: View {
    let tag: SuggestTag

    var body: some View {
        HStack(spacing: 12) {
            Text(tag.icon ?? "#")
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.label)
                Text(tag.tagType.wire.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
