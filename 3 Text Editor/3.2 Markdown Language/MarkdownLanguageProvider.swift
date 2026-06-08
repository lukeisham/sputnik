import AppKit

/// Detects Markdown context at the cursor and pushes a ghost-text suggestion.
///
/// Debounced via Foundation 2.7 `DebounceTimer` (SC-3, no re-implementation here).
/// Suggestions render through the shared `GhostTextOverlay` from 3.1 (SC-2).
/// Pattern analysis runs on `Task(priority: .utility)` (SW-1, SR-4).
@MainActor
public final class MarkdownLanguageProvider {

    // MARK: - Dependencies

    private weak var textView: NSTextView?
    private weak var ghostOverlay: GhostTextOverlay?
    private let settings: SettingsStore
    private let debounce = DebounceTimer()

    public init(textView: NSTextView, ghostOverlay: GhostTextOverlay, settings: SettingsStore) {
        self.textView     = textView
        self.ghostOverlay = ghostOverlay
        self.settings     = settings
    }

    // MARK: - Public interface

    /// Call on every keypress while `EditorMode` is `.markdown`.
    public func onKeypress() {
        debounce.schedule(delay: settings.markdownDebounceInterval) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.generateSuggestion()
            }
        }
    }

    // MARK: - Suggestion generation

    private func generateSuggestion() async {
        guard let textView, let storage = textView.textStorage else { return }
        let cursorPos = textView.selectedRange().location
        guard cursorPos > 0 else { ghostOverlay?.clear(); return }
        let text = storage.string

        let suggestion = await Task(priority: .utility) { [text, cursorPos] in
            Self.suggest(in: text, cursorPos: cursorPos)
        }.value

        if let s = suggestion {
            ghostOverlay?.show(s)
        } else {
            ghostOverlay?.clear()
        }
    }

    // MARK: - Pattern matching (runs off main actor)

    private static func suggest(in text: String, cursorPos: Int) -> String? {
        let safeOffset = min(cursorPos, text.count)
        let idx        = text.index(text.startIndex, offsetBy: safeOffset)
        let prefix     = String(text[..<idx])
        guard let currentLine = prefix.components(separatedBy: "\n").last else { return nil }

        // Heading with no trailing space yet: "#", "##", "###" → suggest " "
        if currentLine.range(of: #"^#{1,6}$"#, options: .regularExpression) != nil {
            return " "
        }

        // List item prefix: "- " or "* " → suggest a placeholder word
        if currentLine.hasSuffix("- ") || currentLine.hasSuffix("* ") {
            return "item"
        }

        // Open link bracket: "[" → suggest "link text](url)"
        if currentLine.hasSuffix("[") {
            return "link text](url)"
        }

        // Fenced code block opener: "```" alone on the line → suggest language
        if currentLine == "```" {
            return "swift"
        }

        return nil
    }
}
