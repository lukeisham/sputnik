import Foundation

/// A single Markdown Help topic conforming to `HelpTopicProtocol`.
///
/// `body` is CommonMark / GFM Markdown rendered live by the app's Markdown pipeline.
/// `exampleCode` pairs raw Markdown source with its rendered output via a "Render" toggle.
public struct MarkdownHelpContent: HelpTopicProtocol {
    public let id: String
    public let title: String
    public let category: String
    /// Full Markdown body for the topic. May contain `@{help:TOPIC_ID}` cross-reference links.
    public let body: String
    public let searchTerms: [String]
    public let relatedTopics: [String]
    /// Optional raw Markdown snippet shown as source + rendered side-by-side with a toggle.
    public let exampleCode: String?

    public init(
        id: String,
        title: String,
        category: String,
        body: String,
        searchTerms: [String] = [],
        relatedTopics: [String] = [],
        exampleCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.searchTerms = searchTerms
        self.relatedTopics = relatedTopics
        self.exampleCode = exampleCode
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.3 Markdown Help/index.json`.
public struct MarkdownHelpIndexFile: Codable, Sendable {
    public let topics: [MarkdownHelpContent]
}
