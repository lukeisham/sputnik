import Foundation

// MARK: - Structural Level

/// Categorizes a grammar topic as addressing structural or lexical language features.
///
/// **Structural** topics cover sentence architecture: subject/object roles, phrase types,
/// clause relationships, verb agreement, modifier placement, and punctuation. These are
/// prioritized when the user selects a multi-word phrase.
///
/// **Lexical** topics cover word-level concerns: spelling, homophones (their/there/they're),
/// word choice (usage), and style. Single-word selections default to lexical matching.
public enum GrammarStructuralLevel: String, Codable, Sendable {
    case structural
    case lexical

    /// Default level when decoding from older data or when level is not specified.
    public static var defaultValue: Self { .lexical }
}

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
    /// Categorizes this topic as structural (sentence architecture) or lexical (word-level).
    /// Used to prioritize structural topics when user selects multi-word phrases.
    public let structuralLevel: GrammarStructuralLevel

    public init(
        id: String,
        title: String,
        category: String,
        body: String,
        searchTerms: [String] = [],
        relatedTopics: [String] = [],
        structuralLevel: GrammarStructuralLevel = .lexical
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.searchTerms = searchTerms
        self.relatedTopics = relatedTopics
        self.structuralLevel = structuralLevel
    }
}

// MARK: - Codable Conformance

extension GrammarHelpContent: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case body
        case searchTerms
        case relatedTopics
        case structuralLevel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        body = try container.decode(String.self, forKey: .body)
        searchTerms = try container.decode([String].self, forKey: .searchTerms)
        relatedTopics = try container.decode([String].self, forKey: .relatedTopics)
        structuralLevel = try container.decodeIfPresent(
            GrammarStructuralLevel.self,
            forKey: .structuralLevel
        ) ?? .lexical
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(body, forKey: .body)
        try container.encode(searchTerms, forKey: .searchTerms)
        try container.encode(relatedTopics, forKey: .relatedTopics)
        try container.encode(structuralLevel, forKey: .structuralLevel)
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.5 Grammar Help/index.json`.
public struct GrammarHelpIndexFile: Codable, Sendable {
    public let topics: [GrammarHelpContent]
}
