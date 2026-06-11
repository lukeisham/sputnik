import Foundation

/// Loads and searches the Grammar Help topic index.
///
/// Loading happens once on first access (off-main-thread via actor isolation).
/// All search and lookup operations are safe to `await` from `@MainActor` callers.
/// Grammar Help includes `searchByTerm(_:)` for targeted fuzzy-match search across
/// the `searchTerms` field, which is the key feature for context-sensitive lookup.
public actor GrammarHelpIndex {

    public static let shared = GrammarHelpIndex()

    private var topics: [GrammarHelpContent] = []
    private var didLoad = false

    private init() {}

    // MARK: - Public API

    /// All topics, loading from bundle on first call.
    public func allTopics() async -> [GrammarHelpContent] {
        await ensureLoaded()
        return topics
    }

    /// All unique category names in order of first appearance.
    public func categories() async -> [String] {
        await ensureLoaded()
        var seen: [String] = []
        for t in topics where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }

    /// Full-text search across title, category, searchTerms, and body.
    public func search(query: String) async -> [GrammarHelpContent] {
        await ensureLoaded()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return topics }
        return topics.filter { t in
            t.title.lowercased().contains(q)
                || t.category.lowercased().contains(q)
                || t.searchTerms.contains { $0.lowercased().contains(q) }
                || t.body.lowercased().contains(q)
        }
    }

    /// Targeted fuzzy-match search across the `searchTerms` field and title only.
    ///
    /// This is the primary lookup method for context-sensitive Grammar Help — it maps
    /// a right-clicked word (or its close misspelling) to matching topics without
    /// false positives from body text. Searches `searchTerms` first (exact and substring
    /// match), then falls back to title matching.
    public func searchByTerm(_ term: String) async -> [GrammarHelpContent] {
        await ensureLoaded()
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return [] }

        // Score each topic: exact searchTerms match = highest, substring match = medium,
        // title match = lower priority.
        var scored: [(topic: GrammarHelpContent, score: Int)] = []
        for topic in topics {
            var score = 0
            let lowerTitle = topic.title.lowercased()
            // Exact match on search term
            if topic.searchTerms.contains(where: { $0.lowercased() == t }) {
                score += 10
            }
            // Substring match on search term
            if topic.searchTerms.contains(where: { $0.lowercased().contains(t) }) {
                score += 5
            }
            // Title match
            if lowerTitle.contains(t) {
                score += 3
            }
            if score > 0 {
                scored.append((topic, score))
            }
        }
        return scored.sorted { $0.score > $1.score }.map { $0.topic }
    }

    /// Returns the topic with the given ID, or `nil` if not found.
    public func topic(id: String) async -> GrammarHelpContent? {
        await ensureLoaded()
        return topics.first { $0.id == id }
    }

    // MARK: - Private

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        guard
            let url = Bundle.module.url(
                forResource: "grammar_help_index",
                withExtension: "json",
                subdirectory: "9.5 Grammar Help"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(GrammarHelpIndexFile.self, from: data)
        else { return }
        topics = file.topics
    }
}
