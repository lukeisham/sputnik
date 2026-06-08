import Foundation

/// Loads and searches the Markdown Help topic index.
public actor MarkdownHelpIndex {

    public static let shared = MarkdownHelpIndex()

    private var topics: [MarkdownHelpContent] = []
    private var didLoad = false

    private init() {}

    // MARK: - Public API

    public func allTopics() async -> [MarkdownHelpContent] {
        await ensureLoaded()
        return topics
    }

    public func categories() async -> [String] {
        await ensureLoaded()
        var seen: [String] = []
        for t in topics where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }

    public func search(query: String) async -> [MarkdownHelpContent] {
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

    public func topic(id: String) async -> MarkdownHelpContent? {
        await ensureLoaded()
        return topics.first { $0.id == id }
    }

    // MARK: - Private

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        guard
            let url = Bundle.main.url(
                forResource: "index",
                withExtension: "json",
                subdirectory: "9.3 Markdown Help"),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(MarkdownHelpIndexFile.self, from: data)
        else { return }
        topics = file.topics
    }
}
