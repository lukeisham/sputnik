import AppKit
import FoundationModule

/// Provides inline ghost-text spelling completions from the macOS dictionary.
///
/// When the user types a partial word and `writingAssist.isEnabled(.autoComplete, for: .spelling)`
/// is on, this provider asks `NSSpellChecker` for completions and shows the top result's
/// suffix (the part beyond what the user already typed) via the shared `GhostTextOverlay`.
///
/// Only active in `.plainText` mode — language-specific providers (Markdown/HTML/ASCII)
/// cover completions in their own modes, avoiding ghost-overlay races.
///
/// Reuses the parent checker's `spellDocumentTag` so ignore-word state is shared.
@MainActor
public final class SpellingCompletionProvider {

    // MARK: - Dependencies

    private weak var textView: NSTextView?
    private weak var ghostOverlay: GhostTextOverlay?
    private let settings: SettingsStore
    private let spellDocumentTag: Int
    private let debounce = DebounceTimer()

    public init(
        textView: NSTextView,
        ghostOverlay: GhostTextOverlay,
        settings: SettingsStore,
        spellDocumentTag: Int
    ) {
        self.textView = textView
        self.ghostOverlay = ghostOverlay
        self.settings = settings
        self.spellDocumentTag = spellDocumentTag
    }

    // MARK: - Public interface

    /// Call on every keypress in `.plainText` mode when spelling auto-complete is enabled.
    public func onKeypress() {
        guard settings.writingAssist.isEnabled(.autoComplete, for: .spelling) else {
            ghostOverlay?.clear()
            return
        }
        debounce.schedule(delay: settings.spellingAutoCompleteStep.timeInterval) { [weak self] in
            Task { @MainActor [weak self] in
                self?.generateCompletion()
            }
        }
    }

    // MARK: - Completion

    private func generateCompletion() {
        guard settings.writingAssist.isEnabled(.autoComplete, for: .spelling),
            let textView,
            let storage = textView.textStorage,
            storage.length > 0
        else {
            ghostOverlay?.clear()
            return
        }

        let cursorPos = textView.selectedRange().location
        guard cursorPos > 0 else {
            ghostOverlay?.clear()
            return
        }

        // Walk back to find the start of the partial word (letters only).
        let nsStr = storage.string as NSString
        var wordStart = cursorPos
        while wordStart > 0 {
            let c = nsStr.character(at: wordStart - 1)
            guard let scalar = Unicode.Scalar(c), Character(scalar).isLetter else { break }
            wordStart -= 1
        }
        let wordLength = cursorPos - wordStart
        guard wordLength >= 2 else {
            ghostOverlay?.clear()
            return
        }

        let partialRange = NSRange(location: wordStart, length: wordLength)
        let partialWord = nsStr.substring(with: partialRange)
        let fullText = storage.string
        let checker = NSSpellChecker.shared
        let completionList = checker.completions(
            forPartialWordRange: partialRange,
            in: fullText,
            language: settings.spellCheckLocale,
            inSpellDocumentWithTag: spellDocumentTag
        )

        guard let topMatch = completionList?.first,
            topMatch.lowercased().hasPrefix(partialWord.lowercased()),
            topMatch.lowercased() != partialWord.lowercased()
        else {
            ghostOverlay?.clear()
            return
        }

        // Show only the suffix — the part after what the user already typed.
        let suffix = String(topMatch.dropFirst(partialWord.count))
        if suffix.isEmpty {
            ghostOverlay?.clear()
        } else {
            ghostOverlay?.show(suffix)
        }
    }
}
