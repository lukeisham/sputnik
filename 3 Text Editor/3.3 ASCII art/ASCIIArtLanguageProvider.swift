import AppKit
import FoundationModule

/// Detects box-drawing sequences at the cursor and dispatches ghost-text or block completion.
///
/// Tier 1 auto-completion — typing-triggered, no manual action required.
/// Debounced via Foundation 2.7 `DebounceTimer` (SC-3).
/// Renders through the shared `GhostTextOverlay` from 3.1 (SC-2, SC-8).
/// Pattern analysis runs on `Task(priority: .utility)` (SR-4).
@MainActor
public final class ASCIIArtLanguageProvider {

    // MARK: - Dependencies

    private weak var textView: NSTextView?
    private weak var ghostOverlay: GhostTextOverlay?
    private let blockCompletion: BlockCompletion
    private let settings: SettingsStore
    private let completionProvider: any CompletionProviding
    private let debounce = DebounceTimer()

    public init(
        textView: NSTextView,
        ghostOverlay: GhostTextOverlay,
        blockCompletion: BlockCompletion,
        settings: SettingsStore,
        completionProvider: any CompletionProviding
    ) {
        self.textView = textView
        self.ghostOverlay = ghostOverlay
        self.blockCompletion = blockCompletion
        self.settings = settings
        self.completionProvider = completionProvider
    }

    // MARK: - Public interface

    /// Call on every keypress while `EditorMode` is `.asciiArt`.
    public func onKeypress() {
        debounce.schedule(delay: settings.asciiAutoCompleteStep.timeInterval) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.generateSuggestion()
            }
        }
    }

    // MARK: - Suggestion generation

    private func generateSuggestion() async {
        guard let textView, let storage = textView.textStorage else { return }
        let cursorPos = textView.selectedRange().location
        let text = storage.string

        let result = await Task(priority: .utility) { [text, cursorPos] in
            Self.analyse(text: text, cursorPos: cursorPos)
        }.value

        switch result {
        case .ghost(let s):
            blockCompletion.discard()
            ghostOverlay?.show(s)
            return
        case .block(let payload):
            blockCompletion.stage(payload)
            ghostOverlay?.show(payload.preview)
            return
        case .none:
            blockCompletion.discard()
        }

        // Corpus fallback — only when Auto-Complete is enabled for ASCII Art.
        guard settings.writingAssist.isEnabled(.autoComplete, for: .asciiArt) else {
            ghostOverlay?.clear()
            return
        }

        let wordPrefix = await Task(priority: .utility) { [text, cursorPos] in
            Self.currentWordPrefix(in: text, upTo: cursorPos)
        }.value

        guard wordPrefix.count >= 2 else {
            ghostOverlay?.clear()
            return
        }

        let query = CompletionQuery(
            language: .asciiArt, prefix: wordPrefix, fullText: text, cursorOffset: cursorPos
        )
        let candidates = await completionProvider.completions(query)

        if let match = candidates.first {
            let suffix = String(match.dropFirst(wordPrefix.count))
            suffix.isEmpty ? ghostOverlay?.clear() : ghostOverlay?.show(suffix)
        } else {
            ghostOverlay?.clear()
        }
    }

    // MARK: - Word prefix extraction (off main actor)

    private static func currentWordPrefix(in text: String, upTo cursorPos: Int) -> String {
        let safeOffset = min(cursorPos, text.count)
        guard safeOffset > 0 else { return "" }
        let end = text.index(text.startIndex, offsetBy: safeOffset)
        var i = end
        while i > text.startIndex {
            let prev = text.index(before: i)
            let c = text[prev]
            guard c.isLetter || c.isNumber else { break }
            i = prev
        }
        return String(text[i..<end])
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
        let idx = text.index(text.startIndex, offsetBy: safeOffset)
        let prefix = String(text[..<idx])
        guard let currentLine = prefix.components(separatedBy: "\n").last else { return .none }

        // ASCII box frame starter: `+--` or `┌─` → offer a full box via BlockCompletion
        if currentLine.hasSuffix("+--") || currentLine.hasSuffix("┌─") {
            let frame = "+--------+\n|        |\n+--------+"
            let payload = BlockCompletion.Payload(
                pattern: String(currentLine.suffix(3)),
                frame: frame,
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
