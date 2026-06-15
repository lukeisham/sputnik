import Foundation
import FoundationModule

/// Provides context-sensitive JSON Help lookups from the JSON editor.
///
/// When the user invokes "Look Up Help" while editing JSON, the editor extracts
/// a token from the text around the cursor and passes it here. The coordinator
/// matches JSON keywords, type names, and structural tokens to the most relevant
/// help topic and returns its ID.
///
/// Also exposes `openHelp(for:)` so callers (e.g. `ContentView` or a menu command)
/// can programmatically open a topic in the panel.
@MainActor
public final class JSONHelpCoordinator: ObservableObject {

    public static let shared = JSONHelpCoordinator()

    /// Called when a help topic should be opened. Assign a closure that writes to
    /// `AppState.requestedHelpTarget`; capture `AppState` weakly to avoid a retain cycle.
    public var onNavigate: ((HelpRequest) -> Void)?

    // MARK: - Init

    private init() {}

    // MARK: - Context Lookup

    /// Token patterns that map to help topic IDs.
    private static let tokenTopicMap: [String: String] = [
        // Types
        "string": "types/string",
        "number": "types/number",
        "integer": "types/number",
        "float": "types/number",
        "boolean": "types/boolean",
        "bool": "types/boolean",
        "true": "types/boolean",
        "false": "types/boolean",
        "null": "types/null",
        "array": "types/array",
        "object": "types/object",
        // Structure
        "{": "structure/objects",
        "}": "structure/objects",
        "[": "structure/arrays",
        "]": "structure/arrays",
        ":": "structure/key-value",
        ",": "structure/key-value",
        // Common patterns
        "key": "structure/key-value",
        "value": "structure/key-value",
        "nested": "patterns/nesting",
        "schema": "patterns/schema",
        "validate": "patterns/validation",
        "pretty": "tools/formatting",
        "format": "tools/formatting",
        "minify": "tools/formatting",
        "parse": "tools/parsing",
        "stringify": "tools/parsing",
        "json5": "formats/json5",
        "jsonld": "formats/json-ld",
        "geojson": "formats/geojson",
        "unicode": "types/string",
        "escape": "types/string",
    ]

    /// Extracts a token from text around the cursor and returns the best-matching
    /// help topic ID, or `nil` if nothing matches.
    public func lookupContext(
        fullText: String,
        cursorOffset: Int,
        selectedText: String?
    ) -> String? {
        if let selected = selectedText, !selected.isEmpty {
            if let match = Self.matchToken(selected.trimmingCharacters(in: .whitespaces)) {
                return match
            }
        }
        guard let token = extractTokenAroundCursor(fullText, cursorOffset) else { return nil }
        return Self.matchToken(token)
    }

    // MARK: - Programmatic Open

    /// Opens the help panel to the topic with the given ID, if registered.
    public func openHelp(for topicID: String) {
        onNavigate?(HelpRequest(kind: .json, topicID: topicID))
    }

    // MARK: - Private Helpers

    private static func matchToken(_ token: String) -> String? {
        let lower = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return tokenTopicMap[lower]
    }

    private func extractTokenAroundCursor(_ text: String, _ offset: Int) -> String? {
        guard offset >= 0, offset <= text.count else { return nil }
        let charCount = text.count
        let startIdx = min(offset, charCount)
        let clamped = startIdx > 0 ? min(startIdx, charCount - 1) : 0

        var tokenStart = clamped
        while tokenStart > 0 {
            let prev = tokenStart - 1
            let char = text[text.index(text.startIndex, offsetBy: prev)]
            if char.isWhitespace || char == "\"" || char == ":" || char == "{" || char == "["
                || char == "," || char == "}" || char == "]"
            {
                tokenStart = prev + 1
                break
            }
            tokenStart = prev
        }

        var tokenEnd = clamped
        while tokenEnd < charCount {
            let char = text[text.index(text.startIndex, offsetBy: tokenEnd)]
            if char.isWhitespace || char == "\"" || char == ":" || char == "{" || char == "["
                || char == "," || char == "}" || char == "]"
            {
                break
            }
            tokenEnd += 1
        }

        guard tokenStart < tokenEnd else { return nil }
        let startStrIdx = text.index(text.startIndex, offsetBy: tokenStart)
        let endStrIdx = text.index(text.startIndex, offsetBy: tokenEnd)
        return String(text[startStrIdx..<endStrIdx])
    }
}
