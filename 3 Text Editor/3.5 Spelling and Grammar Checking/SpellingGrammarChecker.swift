import AppKit

/// Real-time spelling and grammar checker wrapping `NSSpellChecker`.
///
/// Subscribes to text changes; writes red (spelling) and orange (grammar) underline
/// attributes to `NSTextStorage` after a debounce quiet period, and maintains a parallel
/// `GrammarAnnotation` model the editor can hit-test on click.
///
/// **Spelling-over-grammar priority:** when a grammar issue overlaps a spelling issue, the
/// grammar annotation is kept but marked *suppressed* (not rendered), so only the red
/// spelling underline shows. Fixing or dismissing the spelling issue triggers a re-check,
/// after which the now-unsuppressed grammar underline surfaces in orange.
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

    // MARK: - Annotation model (hit-testable by the editor)

    /// The current spelling/grammar issues, including suppressed grammar ones. Rebuilt on
    /// every check. Read-only to collaborators; the editor queries it via `annotation(at:)`.
    public private(set) var annotations: [GrammarAnnotation] = []

    /// Grammar phrases the user has dismissed this session. Re-checks exclude them.
    /// (Spelling dismissals use `NSSpellChecker.ignoreWord`, which the document tag honours.)
    private var ignoredGrammarPhrases: Set<String> = []

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

    /// Runs the check immediately (no debounce). Used after a popover Fix/Dismiss so the
    /// underlines and suppression state update without waiting for the next debounce pass.
    public func recheckNow() {
        runCheck()
    }

    /// Returns the rendered (non-suppressed) annotation containing `location`, or `nil`.
    /// Reads the in-memory model only — no re-scan (SR-4).
    public func annotation(at location: Int) -> GrammarAnnotation? {
        annotations.first { !$0.isSuppressed && NSLocationInRange(location, $0.range) }
    }

    /// Dismisses an annotation: spelling words are added to `NSSpellChecker`'s ignore list
    /// for this document; grammar phrases are added to the local ignored set. A re-check
    /// then clears the underline (and may surface a grammar issue the dismissed spelling
    /// word was hiding).
    public func dismiss(_ annotation: GrammarAnnotation) {
        guard let storage = textView?.textStorage else { return }
        let range = annotation.range
        // Guard against ranges invalidated by a concurrent edit (SR-2).
        guard range.location != NSNotFound,
              range.location + range.length <= storage.length else { return }

        let nsString = storage.string as NSString
        let phrase = nsString.substring(with: range)

        switch annotation.kind {
        case .spelling:
            NSSpellChecker.shared.ignoreWord(phrase, inSpellDocumentWithTag: spellDocumentTag)
        case .grammar:
            ignoredGrammarPhrases.insert(phrase)
        }

        runCheck()
    }

    // MARK: - Checking

    private func runCheck() {
        guard
            viewModel?.spellCheckActive == true,
            let textView,
            let storage = textView.textStorage,
            storage.length > 0
        else {
            annotations = []
            return
        }

        let text       = storage.string
        let nsString   = text as NSString
        let fullRange  = NSRange(location: 0, length: nsString.length)
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

        var newAnnotations: [GrammarAnnotation] = []
        var spellingRanges: [NSRange] = []

        // First pass: spelling. Ignored words are already excluded by `check` (same tag).
        for result in results where result.resultType == .spelling {
            let range = result.range
            guard range.location != NSNotFound,
                  range.location + range.length <= storage.length else { continue }
            spellingRanges.append(range)
            let guesses = checker.guesses(
                forWordRange:           range,
                in:                     text,
                language:               settings.spellCheckLocale,
                inSpellDocumentWithTag: spellDocumentTag
            ) ?? []
            newAnnotations.append(
                GrammarAnnotation(range: range, kind: .spelling, suggestions: guesses)
            )
        }

        // Second pass: grammar. Skip dismissed phrases; suppress those overlapping spelling.
        for result in results where result.resultType == .grammar {
            let range = result.range
            guard range.location != NSNotFound,
                  range.location + range.length <= storage.length else { continue }
            let phrase = nsString.substring(with: range)
            if ignoredGrammarPhrases.contains(phrase) { continue }

            let suppressed = spellingRanges.contains {
                NSIntersectionRange($0, range).length > 0
            }
            var corrections: [String] = []
            for detail in result.grammarDetails ?? [] {
                if let fixes = detail[NSGrammarCorrections] as? [String] {
                    corrections.append(contentsOf: fixes)
                }
            }
            newAnnotations.append(
                GrammarAnnotation(
                    range: range,
                    kind: .grammar,
                    suggestions: corrections,
                    isSuppressed: suppressed
                )
            )
        }

        annotations = newAnnotations

        // Render: clear previous underlines, then draw only non-suppressed annotations.
        storage.beginEditing()
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.underlineColor, range: fullRange)
        for annotation in newAnnotations where !annotation.isSuppressed {
            storage.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.single.rawValue,
                                 range: annotation.range)
            let color: NSColor = annotation.kind == .spelling ? .systemRed : .systemOrange
            storage.addAttribute(.underlineColor, value: color, range: annotation.range)
        }
        storage.endEditing()
    }
}
