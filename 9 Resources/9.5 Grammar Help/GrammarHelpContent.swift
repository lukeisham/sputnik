import Foundation

/// A single Grammar Help topic conforming to `HelpTopicProtocol`.
///
/// `searchTerms` is the critical fuzzy-match field for Grammar Help: it maps arbitrary
/// words a user right-clicks (e.g. "there", "their", "they're") to this topic.
/// The body uses `✅` / `❌` blocks to show correct and incorrect usage.
public struct GrammarHelpContent: HelpTopicProtocol {
    public let id: String
    public let title: String
    public let category: String
    /// Markdown body. ✅ lines show correct usage; ❌ lines show incorrect usage.
    public let body: String
    /// Fuzzy-match aliases used to map right-clicked words to this topic.
    public let searchTerms: [String]
    public let relatedTopics: [String]

    public init(
        id: String,
        title: String,
        category: String,
        body: String,
        searchTerms: [String] = [],
        relatedTopics: [String] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.searchTerms = searchTerms
        self.relatedTopics = relatedTopics
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.5 Grammar Help/index.json`.
public struct GrammarHelpIndexFile: Codable, Sendable {
    public let topics: [GrammarHelpContent]
}
