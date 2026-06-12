import Foundation

// MARK: - Help Level

/// The skill level of an ASCII Art Help topic.
///
/// - `basic`: Typed box-drawing diagrams (frames, lines, boxes, connectors, dividers).
/// - `advanced`: Studio features (image→ASCII, dithering, brightness/contrast, editing tools).
public enum ASCIIHelpLevel: String, Codable, Sendable, CaseIterable {
    case basic
    case advanced

    /// User-facing label for UI display.
    public var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .advanced: return "Advanced"
        }
    }
}

/// A single ASCII Art Help topic conforming to `HelpTopicProtocol`.
///
/// `body` is Markdown text; `relatedArtIDs` references ASCII Library records whose
/// art is injected wherever the body contains an `@{art:ID}` placeholder.
public struct ASCIIArtHelpContent: HelpTopicProtocol {
    public let id: String
    public let title: String
    public let category: String
    /// Skill level of this topic (defaults to `.basic` for backward compatibility, SR-2).
    public let level: ASCIIHelpLevel
    /// Markdown body. May contain `@{art:RECORD_ID}` placeholders resolved at display time
    /// via `ASCIILibrary.art(id:)`.
    public let body: String
    public let searchTerms: [String]
    public let relatedTopics: [String]
    /// ASCII Library record IDs referenced inline by this topic.
    public let relatedArtIDs: [String]
    /// A short before/after code snippet shown in a dedicated code block.
    public let exampleCode: String?

    public init(
        id: String,
        title: String,
        category: String,
        level: ASCIIHelpLevel = .basic,
        body: String,
        searchTerms: [String] = [],
        relatedTopics: [String] = [],
        relatedArtIDs: [String] = [],
        exampleCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.level = level
        self.body = body
        self.searchTerms = searchTerms
        self.relatedTopics = relatedTopics
        self.relatedArtIDs = relatedArtIDs
        self.exampleCode = exampleCode
    }
}

// MARK: - Codable (with safe default for backward compatibility, SR-2)

extension ASCIIArtHelpContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, category, level, body, searchTerms, relatedTopics, relatedArtIDs,
            exampleCode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.category = try container.decode(String.self, forKey: .category)
        // SR-2: decode with .basic default so older index.json files still load.
        self.level = try container.decodeIfPresent(ASCIIHelpLevel.self, forKey: .level) ?? .basic
        self.body = try container.decode(String.self, forKey: .body)
        self.searchTerms = try container.decodeIfPresent([String].self, forKey: .searchTerms) ?? []
        self.relatedTopics =
            try container.decodeIfPresent([String].self, forKey: .relatedTopics) ?? []
        self.relatedArtIDs =
            try container.decodeIfPresent([String].self, forKey: .relatedArtIDs) ?? []
        self.exampleCode = try container.decodeIfPresent(String.self, forKey: .exampleCode)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(level, forKey: .level)
        try container.encode(body, forKey: .body)
        try container.encode(searchTerms, forKey: .searchTerms)
        try container.encode(relatedTopics, forKey: .relatedTopics)
        try container.encode(relatedArtIDs, forKey: .relatedArtIDs)
        try container.encodeIfPresent(exampleCode, forKey: .exampleCode)
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.2 ASCII art Help/ascii_art_help_index.json`.
public struct ASCIIArtHelpIndexFile: Codable, Sendable {
    public let topics: [ASCIIArtHelpContent]
}
