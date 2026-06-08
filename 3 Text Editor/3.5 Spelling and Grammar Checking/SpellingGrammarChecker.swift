import AppKit

/// Real-time spelling and grammar checker wrapping `NSSpellChecker`.
///
/// Subscribes to text changes; writes red (spelling) and green (grammar) underline
/// attributes to `NSTextStorage` after a debounce quiet period.
///
/// Only active when `EditorViewModel.spellCheckActive` is `true`.
/// All `NSSpellChecker` calls and `NSTextStorage` attribute mutations are on
/// `@MainActor` — required by AppKit.
@MainActor
public final class SpellingGrammarChecker {

    // MARK: - Dependencies

    private weak var textView:  NSTextView?
    private weak var viewModel: EditorViewModel?
    private let settings: SettingsStore
    private let debounce = DebounceTimer()

    /// `NSSpellChecker` document tag that identifies this editing session.
    /// Exposed so `QuickfixPresenter` can share the same tag.
    public let spellDocumentTag: Int = NSSpellChecker.uniqueSpellDocumentTag()

    public init(textView: NSTextView, viewModel: EditorViewModel, settings: SettingsStore) {
        self.textView  = textView
        self.viewModel = viewModel
        self.settings  = settings
    }

    deinit {
        // Close the document session to release resources in NSSpellChecker.
        NSSpellChecker.shared.closeSpellDocument(withTag: spellDocumentTag)
    }

    // MARK: - Public interface

    /// Call on every `NSTextStorage` change when `spellCheckActive` is `true`.
    public func onTextChange() {
        guard viewModel?.spellCheckActive == true else { return }
        debounce.schedule(delay: settings.spellCheckDebounceInterval) { [weak self] in
            Task { @MainActor [weak self] in
                self?.runCheck()
            }
        }
    }

    // MARK: - Checking

    private func runCheck() {
        guard
            viewModel?.spellCheckActive == true,
            let textView,
            let storage = textView.textStorage,
            storage.length > 0
        else { return }

        let text       = storage.string
        let fullRange  = NSRange(location: 0, length: (text as NSString).length)
        let checker    = NSSpellChecker.shared

        if let locale = settings.spellCheckLocale {
            checker.setLanguage(locale)
        }
        let results = checker.check(
            text,
            range:                  fullRange,
            types:                  NSTextCheckingAllSystemTypes,
            options:                nil,
            inSpellDocumentWithTag: spellDocumentTag,
            orthography:            nil,
            wordCount:              nil
        )

        storage.beginEditing()
        // Clear previous underlines before writing fresh results.
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.underlineColor, range: fullRange)

        for result in results {
            let range = result.range
            // Guard against ranges that became stale due to concurrent edits — no-op.
            guard range.location != NSNotFound,
                  range.location + range.length <= storage.length else { continue }

            switch result.resultType {
            case .spelling:
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: range)
                storage.addAttribute(.underlineColor, value: NSColor.systemRed, range: range)
            case .grammar:
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: range)
                storage.addAttribute(.underlineColor, value: NSColor.systemGreen, range: range)
            default:
                break
            }
        }
        storage.endEditing()
    }
}
