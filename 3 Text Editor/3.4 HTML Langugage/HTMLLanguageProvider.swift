import AppKit

/// Generates HTML tag and attribute completions at the cursor using ghost text.
///
/// Only active when `EditorViewModel.htmlModeActive` is `true` (SC-10 gate).
/// Debounced via Foundation 2.7 `DebounceTimer` (SC-3).
/// Renders through the shared `GhostTextOverlay` from 3.1 (SC-2).
///
/// ISS-004: `debounceInterval` and `suggestionsEnabled` should come from `SettingsStore`
/// (Foundation 2.3). Using local defaults until that setting is exposed.
@MainActor
public final class HTMLLanguageProvider {

    // MARK: - Dependencies

    private weak var textView:    NSTextView?
    private weak var ghostOverlay: GhostTextOverlay?
    private weak var viewModel:   EditorViewModel?
    private let debounce = DebounceTimer()

    // ISS-004: local default — replace with SettingsStore when Foundation 2.3 is ready.
    private let debounceInterval: TimeInterval = 0.20

    public init(
        textView:     NSTextView,
        ghostOverlay: GhostTextOverlay,
        viewModel:    EditorViewModel
    ) {
        self.textView     = textView
        self.ghostOverlay  = ghostOverlay
        self.viewModel    = viewModel
    }

    // MARK: - Public interface

    /// Call on every keypress in `.html` mode.
    public func onKeypress() {
        guard viewModel?.htmlModeActive == true else { ghostOverlay?.clear(); return }
        debounce.schedule(delay: debounceInterval) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.generateSuggestion()
            }
        }
    }

    // MARK: - Suggestion generation

    private func generateSuggestion() async {
        guard let textView, let storage = textView.textStorage,
              viewModel?.htmlModeActive == true else { return }
        let cursorPos = textView.selectedRange().location
        let text      = storage.string

        let suggestion = await Task(priority: .utility) { [text, cursorPos] in
            HTMLLanguageProvider.suggest(in: text, cursorPos: cursorPos)
        }.value

        if let s = suggestion {
            ghostOverlay?.show(s)
        } else {
            ghostOverlay?.clear()
        }
    }

    // MARK: - Pattern matching (off main actor)

    /// Returns a completion string for the text prefix ending at `cursorPos`, or `nil`.
    static func suggest(in text: String, cursorPos: Int) -> String? {
        let end    = text.index(text.startIndex, offsetBy: min(cursorPos, text.count))
        let prefix = String(text[..<end])

        // Partial opening tag `<div` → close and add matching closing tag.
        if let range = prefix.range(of: #"<([a-zA-Z][a-zA-Z0-9]*)$"#, options: .regularExpression) {
            let tag = String(prefix[range]).dropFirst()   // strip the leading `<`
            return ">\n</\(tag)>"
        }

        // Attribute value opener `class="` → close the quote.
        if prefix.hasSuffix("=\"") {
            return "\""
        }

        // Void elements — suggest self-close.
        if prefix.range(
            of: #"<(img|br|hr|input|meta|link)([^>]*)$"#,
            options: .regularExpression
        ) != nil {
            return " />"
        }

        // Common block tag starters for quicker entry.
        let tagMap: [String: String] = [
            "<p":    "></p>",
            "<div":  ">\n</div>",
            "<span": "></span>",
            "<a":    " href=\"\"></a>",
            "<ul":   ">\n  <li></li>\n</ul>",
            "<ol":   ">\n  <li></li>\n</ol>",
            "<h1":   "></h1>",
            "<h2":   "></h2>",
            "<h3":   "></h3>",
        ]
        for (key, value) in tagMap where prefix.hasSuffix(key) {
            return value
        }

        return nil
    }
}
