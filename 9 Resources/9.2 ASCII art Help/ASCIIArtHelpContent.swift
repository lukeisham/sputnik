import Foundation

/// A single ASCII Art Help topic conforming to `HelpTopicProtocol`.
///
/// `body` is Markdown text; `relatedArtIDs` references ASCII Library records whose
/// art is injected wherever the body contains an `@{art:ID}` placeholder.
public struct ASCIIArtHelpContent: HelpTopicProtocol {
    public let id: String
    public let title: String
    public let category: String
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
        body: String,
        searchTerms: [String] = [],
        relatedTopics: [String] = [],
        relatedArtIDs: [String] = [],
        exampleCode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.searchTerms = searchTerms
        self.relatedTopics = relatedTopics
        self.relatedArtIDs = relatedArtIDs
        self.exampleCode = exampleCode
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.2 ASCII art Help/index.json`.
public struct ASCIIArtHelpIndexFile: Codable, Sendable {
    public let topics: [ASCIIArtHelpContent]
}
