import Foundation
import FoundationModule

// MARK: - Markdown Help Coordinator

/// Handles context-sensitive help lookup from the editor (3.2) when the current
/// document type is `.markdown`.
///
/// The coordinator analyses the text around the cursor to detect Markdown syntax
/// patterns (`## ` → heading, `**text**` → bold, `` `code` `` → inline code,
/// `[text](url)` → link, etc.) and maps them to the most relevant help topic.
///
/// All index access happens on `MarkdownHelpIndex.shared` (an actor); results
/// are returned on the caller's isolation domain.
@MainActor
public final class MarkdownHelpCoordinator: ObservableObject {

    // MARK: - Singleton

    public static let shared = MarkdownHelpCoordinator()

    // MARK: - Properties

    /// Called when a help topic should be opened. Assign a closure that writes to
    /// `AppState.requestedHelpTarget`; capture `AppState` weakly to avoid a retain cycle.
    public var onNavigate: ((HelpRequest) -> Void)?

    // MARK: - Syntax-to-topic mapping

    /// Maps syntax patterns detected near the cursor to help topic IDs.
    /// Higher-priority patterns are checked first.
    private static let syntaxTopicMap: [(pattern: String, topicID: String)] = [
        // Code blocks (triple-backtick or 4-space indent)
        ("```", "advanced/code-blocks"),
        ("~~~", "advanced/code-blocks"),

        // Tables (pipe character at start of line)
        ("|", "advanced/tables"),

        // Blockquotes
        ("> ", "advanced/blockquotes"),
        (">", "advanced/blockquotes"),

        // Horizontal rules
        ("---", "advanced/horizontal-rules"),
        ("***", "advanced/horizontal-rules"),
        ("___", "advanced/horizontal-rules"),

        // Images
        ("![", "formatting/images"),
        ("! [", "formatting/images"),

        // Links
        ("[", "formatting/links"),

        // Inline code
        ("`", "formatting/code"),

        // Bold + Italic combinations
        ("***", "formatting/bold-and-italic"),
        ("___", "formatting/bold-and-italic"),
        ("**", "formatting/bold-and-italic"),
        ("__", "formatting/bold-and-italic"),
        ("*", "formatting/bold-and-italic"),
        ("_", "formatting/bold-and-italic"),

        // Headings
        ("###### ", "basics/headings"),
        ("##### ", "basics/headings"),
        ("#### ", "basics/headings"),
        ("### ", "basics/headings"),
        ("## ", "basics/headings"),
        ("# ", "basics/headings"),

        // Lists (unordered)
        ("- ", "formatting/lists"),
        ("* ", "formatting/lists"),
        ("+ ", "formatting/lists"),

        // Lists (ordered)
        ("1. ", "formatting/lists"),
    ]

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Analyses the text around the cursor and returns the best-matching help
    /// topic ID, or `nil` if no syntax pattern is detected.
    ///
    /// - Parameters:
    ///   - fullText: The entire document text.
    ///   - cursorOffset: UTF-16 offset of the cursor (or selected-range start).
    ///   - selectedText: The currently selected word/text, if any.
    /// - Returns: The matching topic ID, or `nil`.
    public func lookupContext(
        fullText: String,
        cursorOffset: Int,
        selectedText: String?
    ) -> String? {
        // 1. If there's selected text, try exact keyword match first
        if let selected = selectedText, !selected.isEmpty {
            if let match = matchKeyword(selected.trimmingCharacters(in: .whitespaces)) {
                return match
            }
        }

        // 2. Extract the line the cursor is on
        guard let line = lineAtCursor(fullText, cursorOffset) else { return nil }

        // 3. Scan the line for syntax patterns (ordered by priority)
        for (syntaxPattern, topicID) in Self.syntaxTopicMap {
            if line.contains(syntaxPattern) {
                return topicID
            }
        }

        return nil
    }

    /// Full-text search across the Markdown Help index.
    ///
    /// - Parameter query: A search string.
    /// - Returns: Matching topics, sorted by relevance.
    public func search(query: String) async -> [MarkdownHelpContent] {
        let index = MarkdownHelpIndex.shared
        return await index.search(query: query)
    }

    /// Returns the best-matching topic for a single word (case-insensitive,
    /// matches against title, search terms, and body).
    public func bestMatch(for word: String) async -> MarkdownHelpContent? {
        let index = MarkdownHelpIndex.shared
        let results = await index.search(query: word)
        guard !results.isEmpty else { return nil }

        let wordLower = word.lowercased()
        if let exact = results.first(where: { $0.title.lowercased() == wordLower }) {
            return exact
        }
        if let exactTerm = results.first(where: { topic in
            topic.searchTerms.contains { $0.lowercased() == wordLower }
        }) {
            return exactTerm
        }
        return results.first
    }

    /// Opens the help panel to a specific topic.
    @discardableResult
    public func openHelp(for topicID: String) async -> Bool {
        let index = MarkdownHelpIndex.shared
        guard await index.topic(id: topicID) != nil else { return false }
        onNavigate?(HelpRequest(kind: .markdown, topicID: topicID))
        return true
    }

    // MARK: - Private Helpers

    /// Matches a selected keyword against a set of known Markdown terms.
    private func matchKeyword(_ word: String) -> String? {
        let lower = word.lowercased()
        switch lower {
        case "heading", "headings", "h1", "h2", "h3", "h4", "h5", "h6", "title":
            return "basics/headings"
        case "bold", "italic", "emphasis", "strong":
            return "formatting/bold-and-italic"
        case "link", "links", "url", "hyperlink":
            return "formatting/links"
        case "image", "images", "img":
            return "formatting/images"
        case "code", "inline", "backtick":
            return "formatting/code"
        case "list", "lists", "bullet", "ordered", "unordered":
            return "formatting/lists"
        case "table", "tables":
            return "advanced/tables"
        case "blockquote", "quote", "block":
            return "advanced/blockquotes"
        case "rule", "hr", "horizontal", "divider":
            return "advanced/horizontal-rules"
        case "gfm", "github", "flavored", "extension":
            return "advanced/gfm-extensions"
        case "markdown", "md":
            return "basics/getting-started"
        default:
            return nil
        }
    }

    /// Returns the full line at the given cursor offset.
    private func lineAtCursor(_ text: String, _ offset: Int) -> String? {
        guard offset >= 0, offset <= text.count else { return nil }

        // Walk backward to find line start
        var lineStart = offset
        while lineStart > 0 {
            let prev = text.index(text.startIndex, offsetBy: lineStart - 1)
            if text[prev] == "\n" { break }
            lineStart -= 1
        }

        // Walk forward to find line end
        var lineEnd = offset
        while lineEnd < text.count {
            let idx = text.index(text.startIndex, offsetBy: lineEnd)
            if text[idx] == "\n" { break }
            lineEnd += 1
        }

        guard lineStart < lineEnd else { return nil }
        let startIdx = text.index(text.startIndex, offsetBy: lineStart)
        let endIdx = text.index(text.startIndex, offsetBy: lineEnd)
        return String(text[startIdx..<endIdx])
    }
}
