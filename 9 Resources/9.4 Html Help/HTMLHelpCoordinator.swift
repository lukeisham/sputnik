import Foundation

/// Provides context-sensitive HTML Help lookups from the HTML editor.
///
/// When the user invokes "Look Up Help" (⌘⇧/) while editing HTML, the editor
/// extracts a token from the text around the cursor and passes it here.
/// The coordinator matches tag names and attribute names to the most relevant
/// help topic and returns its ID.
///
/// Also exposes `openHelp(for:)` so callers (e.g. `ContentView` or a menu command)
/// can programmatically open a topic in the panel.
@MainActor
public final class HTMLHelpCoordinator: ObservableObject {

    public static let shared = HTMLHelpCoordinator()

    /// Called when a help topic should be opened. Assign a closure that writes to
    /// `AppState.requestedHelpTarget`; capture `AppState` weakly to avoid a retain cycle.
    public var onNavigate: ((HelpRequest) -> Void)?

    // MARK: - Init

    private init() {}

    // MARK: - Context Lookup

    /// Tag-name patterns that map to help topic IDs.
    private static let tagTopicMap: [String: String] = [
        "div": "elements/div-and-span",
        "span": "elements/div-and-span",
        "h1": "elements/headings",
        "h2": "elements/headings",
        "h3": "elements/headings",
        "h4": "elements/headings",
        "h5": "elements/headings",
        "h6": "elements/headings",
        "a": "elements/links",
        "img": "elements/images",
        "table": "elements/tables",
        "tr": "elements/tables",
        "td": "elements/tables",
        "th": "elements/tables",
        "thead": "elements/tables",
        "tbody": "elements/tables",
        "form": "elements/forms",
        "input": "elements/forms",
        "button": "elements/forms",
        "select": "elements/forms",
        "textarea": "elements/forms",
        "label": "elements/forms",
        "ul": "elements/lists",
        "ol": "elements/lists",
        "li": "elements/lists",
        "dl": "elements/lists",
        "dt": "elements/lists",
        "dd": "elements/lists",
    ]

    /// Attribute-name patterns that map to help topic IDs.
    private static let attributeTopicMap: [String: String] = [
        "class": "attributes/class-and-id",
        "id": "attributes/class-and-id",
        "style": "attributes/style",
        "href": "elements/links",
        "src": "elements/images",
        "alt": "elements/images",
        "loading": "elements/images",
        "type": "elements/forms",
    ]

    /// Extracts a tag name or attribute name from the text around the cursor
    /// and returns the best-matching help topic ID, or `nil` if nothing matches.
    public func lookupContext(
        fullText: String,
        cursorOffset: Int,
        selectedText: String?
    ) -> String? {
        // 1. If there's selected text, try that first
        if let selected = selectedText, !selected.isEmpty {
            if let match = Self.matchToken(selected.trimmingCharacters(in: .whitespaces)) {
                return match
            }
        }

        // 2. Extract the word or tag around the cursor
        guard let token = extractTokenAroundCursor(fullText, cursorOffset) else {
            return nil
        }

        return Self.matchToken(token)
    }

    // MARK: - Programmatic Open

    /// Opens the help panel to the topic with the given ID, if registered.
    public func openHelp(for topicID: String) {
        onNavigate?(HelpRequest(kind: .html, topicID: topicID))
    }

    // MARK: - Private Helpers

    /// Matches a token against the tag and attribute maps.
    private static func matchToken(_ token: String) -> String? {
        let lower = token.lowercased()

        // Try tag map first
        if let topicID = tagTopicMap[lower] {
            return topicID
        }

        // Then attribute map
        if let topicID = attributeTopicMap[lower] {
            return topicID
        }

        // Check for `data-*` attribute pattern
        if lower.hasPrefix("data-") {
            return "globals/data-attributes"
        }

        // Check for event handler pattern (on*)
        if lower.hasPrefix("on") {
            return "events/onclick-and-events"
        }

        return nil
    }

    /// Extracts the word or HTML tag/attribute token nearest the cursor.
    private func extractTokenAroundCursor(_ text: String, _ offset: Int) -> String? {
        guard offset >= 0, offset <= text.count else { return nil }

        let charCount = text.count

        // Clamp offset
        let startIdx = min(offset, charCount)
        let clamped = startIdx > 0 ? min(startIdx, charCount - 1) : 0

        // Walk backward to find start of token
        var tokenStart = clamped
        while tokenStart > 0 {
            let prev = tokenStart - 1
            let char = text[text.index(text.startIndex, offsetBy: prev)]
            if char.isWhitespace || char == ">" {
                // Stop at whitespace or closing bracket — but include the tag/attr
                if char == ">" {
                    tokenStart = prev + 1
                    break
                }
                tokenStart = prev + 1
                break
            }
            tokenStart = prev
        }

        // Walk forward to find end of token
        var tokenEnd = clamped
        while tokenEnd < charCount {
            let char = text[text.index(text.startIndex, offsetBy: tokenEnd)]
            if char.isWhitespace || char == "=" || char == "<" || char == ">" {
                break
            }
            tokenEnd += 1
        }

        guard tokenStart < tokenEnd else { return nil }

        let startStrIdx = text.index(text.startIndex, offsetBy: tokenStart)
        let endStrIdx = text.index(text.startIndex, offsetBy: tokenEnd)
        var raw = String(text[startStrIdx..<endStrIdx])

        // Strip leading characters like `<` or `"` that aren't part of the name
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<\"'"))

        // If we got an empty string after trimming, try to grab the tag from
        // a few characters before the cursor as a fallback
        guard !raw.isEmpty else {
            // Look backward for an opening `<tag`
            var searchPos = clamped
            while searchPos > 0 {
                searchPos -= 1
                let char = text[text.index(text.startIndex, offsetBy: searchPos)]
                if char == "<" {
                    let tagStart = searchPos + 1
                    var tagEnd = tagStart
                    while tagEnd < charCount {
                        let c = text[text.index(text.startIndex, offsetBy: tagEnd)]
                        if c.isWhitespace || c == ">" {
                            break
                        }
                        tagEnd += 1
                    }
                    if tagEnd > tagStart {
                        return String(
                            text[
                                text.index(
                                    text.startIndex, offsetBy: tagStart)..<text.index(
                                        text.startIndex, offsetBy: tagEnd)])
                    }
                    break
                }
            }
            return nil
        }

        return raw
    }
}
