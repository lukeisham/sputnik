import Foundation

/// A single JSON Help topic conforming to `HelpTopicProtocol`.
public struct JSONHelpContent: HelpTopicProtocol, Codable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    /// Markdown body describing the JSON concept, type, or pattern.
    public let body: String
    public let searchTerms: [String]
    public let relatedTopics: [String]
    /// Optional JSON snippet displayed as a read-only code example.
    public let exampleJSON: String?

    public init(
        id: String,
        title: String,
        category: String,
        body: String,
        searchTerms: [String] = [],
        relatedTopics: [String] = [],
        exampleJSON: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.searchTerms = searchTerms
        self.relatedTopics = relatedTopics
        self.exampleJSON = exampleJSON
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.7 JSON Help/json_help_index.json`.
public struct JSONHelpIndexFile: Codable, Sendable {
    public let topics: [JSONHelpContent]
}
