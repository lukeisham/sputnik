import Foundation

/// A single Style Help topic conforming to `HelpTopicProtocol`.
///
/// Style Help provides writing-style reference topics for prose improvement.
/// Style topics are always guidance-level — there is no structural-vs-lexical
/// distinction.
///
/// Valid categories: `"usage"`, `"composition"`, `"form"`, `"word-usage"`,
/// `"structure"`, `"voice"`.
public struct StyleHelpContent: HelpTopicProtocol {
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

// MARK: - Codable Conformance

extension StyleHelpContent: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case body
        case searchTerms
        case relatedTopics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        body = try container.decode(String.self, forKey: .body)
        searchTerms = try container.decode([String].self, forKey: .searchTerms)
        relatedTopics = try container.decode([String].self, forKey: .relatedTopics)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(body, forKey: .body)
        try container.encode(searchTerms, forKey: .searchTerms)
        try container.encode(relatedTopics, forKey: .relatedTopics)
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.9 Style Help/style_help_index.json`.
public struct StyleHelpIndexFile: Codable, Sendable {
    public let topics: [StyleHelpContent]
}
