import Foundation

/// A single HTML Help topic conforming to `HelpTopicProtocol`.
///
/// `exampleHTML` is a self-contained HTML snippet rendered in a sandboxed
/// `WKWebView` (~200 pt tall) inside the topic content view.
public struct HTMLHelpContent: HelpTopicProtocol {
    public let id: String
    public let title: String
    public let category: String
    /// Markdown body describing the element, attribute, or concept.
    public let body: String
    public let searchTerms: [String]
    public let relatedTopics: [String]
    /// Optional HTML snippet displayed as a live sandboxed demo.
    public let exampleHTML: String?

    public init(
        id: String,
        title: String,
        category: String,
        body: String,
        searchTerms: [String] = [],
        relatedTopics: [String] = [],
        exampleHTML: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.searchTerms = searchTerms
        self.relatedTopics = relatedTopics
        self.exampleHTML = exampleHTML
    }
}

// MARK: - Index container

/// Root container decoded from `9 Resources/9.4 Html Help/index.json`.
public struct HTMLHelpIndexFile: Codable, Sendable {
    public let topics: [HTMLHelpContent]
}
