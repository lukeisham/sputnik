import AppKit

/// Detects box-drawing sequences at the cursor and dispatches ghost-text or block completion.
///
/// Tier 1 auto-completion — typing-triggered, no manual action required.
/// Debounced via Foundation 2.7 `DebounceTimer` (SC-3).
/// Renders through the shared `GhostTextOverlay` from 3.1 (SC-2, SC-8).
/// Pattern analysis runs on `Task(priority: .utility)` (SR-4).
///
/// ISS-004: `debounceInterval` and `asciiTriggerKey` should come from `SettingsStore`
/// (Foundation 2.3). Local default: 0.15 s, trigger key = Tab (built into GhostTextOverlay).
@MainActor
public final class ASCIIArtLanguageProvider {

    // MARK: - Dependencies

    private weak var textView: NSTextView?
    private weak var ghostOverlay: GhostTextOverlay?
    let blockCompletion: BlockCompletion

    // ISS-004: local default — replace with SettingsStore.asciiDebounceInterval when ready.
    private let debounceInterval: TimeInterval = 0.15
    private let debounce = DebounceTimer()

    public init(
        textView: NSTextView,
        ghostOverlay: GhostTextOverlay,
        blockCompletion: BlockCompletion
    ) {
        self.textView       = textView
        self.ghostOverlay   = ghostOverlay
        self.blockCompletion = blockCompletion
    }

    // MARK: - Public interface

    /// Call on every keypress while `EditorMode` is `.asciiArt`.
    public func onKeypress() {
        debounce.schedule(delay: debounceInterval) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.generateSuggestion()
            }
        }
    }

    // MARK: - Suggestion generation

    private func generateSuggestion() async {
        guard let textView, let storage = textView.textStorage else { return }
        let cursorPos = textView.selectedRange().location
        let text      = storage.string

        let result = await Task(priority: .utility) { [text, cursorPos] in
            Self.analyse(text: text, cursorPos: cursorPos)
        }.value

        switch result {
        case .ghost(let s):
            blockCompletion.discard()
            ghostOverlay?.show(s)
        case .block(let payload):
            blockCompletion.stage(payload)
            ghostOverlay?.show(payload.preview)
        case .none:
            blockCompletion.discard()
            ghostOverlay?.clear()
        }
    }

    // MARK: - Analysis result

    enum SuggestionResult: Sendable {
        case ghost(String)
        case block(BlockCompletion.Payload)
        case none
    }

    // MARK: - Analysis (off main actor)

    private static func analyse(text: String, cursorPos: Int) -> SuggestionResult {
        let safeOffset = min(cursorPos, text.count)
        let idx        = text.index(text.startIndex, offsetBy: safeOffset)
        let prefix     = String(text[..<idx])
        guard let currentLine = prefix.components(separatedBy: "\n").last else { return .none }

        // ASCII box frame starter: `+--` or `┌─` → offer a full box via BlockCompletion
        if currentLine.hasSuffix("+--") || currentLine.hasSuffix("┌─") {
            let frame   = "+--------+\n|        |\n+--------+"
            let payload = BlockCompletion.Payload(
                pattern: String(currentLine.suffix(3)),
                frame:   frame,
                preview: "+--------+"
            )
            return .block(payload)
        }

        // Single vertical pipe on its own line → ghost-hint the closing pipe
        if currentLine == "|" {
            return .ghost("        |")
        }

        // Horizontal rule starter: `---` → ghost-hint a longer rule
        if currentLine == "---" {
            return .ghost("--------")
        }

        // Box corner starters: `+` alone → hint the top-right corner
        if currentLine == "+" {
            return .ghost("--------+")
        }

        return .none
    }
}
