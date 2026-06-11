import Foundation

/// Loads and searches the HTML Help topic index.
///
/// Loading happens once on first access (SR-4: off-main-thread via actor isolation).
/// All search and lookup operations are safe to `await` from `@MainActor` callers.
public actor HTMLHelpIndex {

    public static let shared = HTMLHelpIndex()

    private var topics: [HTMLHelpContent] = []
    private var didLoad = false

    private init() {}

    // MARK: - Public API

    /// All topics, loading from bundle on first call.
    public func allTopics() async -> [HTMLHelpContent] {
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
    public func search(query: String) async -> [HTMLHelpContent] {
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

    /// Returns the topic with the given ID, or `nil` if not found.
    public func topic(id: String) async -> HTMLHelpContent? {
        await ensureLoaded()
        return topics.first { $0.id == id }
    }

    // MARK: - Private

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        guard
            let url = Bundle.module.url(
                forResource: "html_help_index",
                withExtension: "json",
                subdirectory: "9.4 Html Help"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(HTMLHelpIndexFile.self, from: data)
        else { return }
        topics = file.topics
    }
}
