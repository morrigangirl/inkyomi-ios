import Foundation
import Observation

/// Persists the user's last `MAX_RECENTS` distinct search queries
/// (most-recent first) in `UserDefaults` under a single key. Stored as a
/// JSON-encoded `[String]`.
///
/// Surfaces in `SearchView` when the input is empty so users can re-run
/// a recent query in one tap. Each new submitted query bubbles its way
/// to the top of the list and de-duplicates case-insensitively.
@MainActor
@Observable
final class RecentSearchesPreferences {
    static let key = "shop.inkcolors.InkYomi.recentSearches"
    private static let maxRecents = 10
    private static let minLength = 2

    /// Most-recent first. Read from UserDefaults at init; subsequent
    /// mutations update the property and persist.
    private(set) var recentQueries: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentQueries = Self.load(defaults: defaults)
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minLength else { return }
        // De-dup case-insensitively, keep the new spelling; cap to MAX.
        var next = [trimmed]
        for q in recentQueries where q.caseInsensitiveCompare(trimmed) != .orderedSame {
            next.append(q)
        }
        if next.count > Self.maxRecents {
            next = Array(next.prefix(Self.maxRecents))
        }
        recentQueries = next
        persist()
    }

    func remove(_ query: String) {
        recentQueries.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        persist()
    }

    func clear() {
        recentQueries = []
        persist()
    }

    private func persist() {
        if recentQueries.isEmpty {
            defaults.removeObject(forKey: Self.key)
            return
        }
        if let data = try? JSONEncoder().encode(recentQueries) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func load(defaults: UserDefaults) -> [String] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
