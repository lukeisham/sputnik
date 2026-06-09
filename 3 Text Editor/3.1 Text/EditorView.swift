import AppKit
import SwiftUI

/// SwiftUI wrapper for the Sputnik text-editing surface.
///
/// SW-3 boundary: `NSViewRepresentable` is required here because `NSTextView` with a custom
/// `NSRulerView` (line numbers), `NSTextStorage` mutation hooks, and per-key delegates cannot
/// be replicated with SwiftUI's `TextEditor`. **This is the only crossing point** between
/// SwiftUI and AppKit in module 3 for the editing surface; everything outside this file
/// (toolbar, search bar, Studio tabs) stays in SwiftUI.
public struct EditorView: NSViewRepresentable {

    var viewModel: EditorViewModel
    var settings: SettingsStore
    var appState: AppState

    public init(viewModel: EditorViewModel, settings: SettingsStore, appState: AppState) {
        self.viewModel = viewModel
        self.settings  = settings
        self.appState  = appState
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // Build a standard scrollable text view, then swap the document view for
        // our EditorTextView subclass so key-event hooks are available.
        let scrollView     = NSTextView.scrollableTextView()
        let textView       = EditorTextView(frame: .zero)
        textView.autoresizingMask = [.width]
        textView.delegate         = context.coordinator
        scrollView.documentView   = textView

        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true

        // Attach line-number ruler.
        let ruler = LineNumberRulerView(scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler  = true
        scrollView.rulersVisible     = true

        // Wire undo manager into the view model so sub-modules can post undo actions.
        viewModel.undoManager = textView.undoManager

        // Create shared overlay and search controller; inject into the text view.
        let overlay  = GhostTextOverlay(textView: textView)
        let search   = SearchController(textView: textView)
        textView.ghostTextOverlay = overlay
        textView.searchController = search

        // Spelling/grammar checker: held strongly by the coordinator (lives as long as the
        // view); the text view holds it weakly for click hit-testing (SW-2).
        let checker = SpellingGrammarChecker(textView: textView,
                                             viewModel: viewModel,
                                             settings: settings)
        textView.spellingChecker = checker
        textView.editorViewModel = viewModel
        textView.settings        = settings

        // Route "Look Up Help" through the Foundation help target (SR-1). Capture weakly
        // so the long-lived text view never retains AppState (SW-2).
        textView.onRequestHelp = { [weak appState] request in
            appState?.requestedHelpTarget = request
        }

        // Completion corpus — created once, shared across all four providers (SR-3).
        let corpus = SputnikCompletionCorpus()

        // Language providers — wired to the shared ghost overlay; one is active per mode.
        let blockCompletion  = BlockCompletion()
        let markdownProvider = MarkdownLanguageProvider(
            textView: textView, ghostOverlay: overlay, settings: settings, completionProvider: corpus
        )
        let htmlProvider = HTMLLanguageProvider(
            textView: textView, ghostOverlay: overlay, viewModel: viewModel,
            settings: settings, completionProvider: corpus
        )
        let asciiProvider = ASCIIArtLanguageProvider(
            textView: textView, ghostOverlay: overlay, blockCompletion: blockCompletion,
            settings: settings, completionProvider: corpus
        )
        let spellingCompletionProvider = SpellingCompletionProvider(
            textView: textView, ghostOverlay: overlay,
            settings: settings, spellDocumentTag: checker.spellDocumentTag
        )

        context.coordinator.textView                  = textView
        context.coordinator.ghostOverlay              = overlay
        context.coordinator.search                    = search
        context.coordinator.checker                   = checker
        context.coordinator.markdownProvider          = markdownProvider
        context.coordinator.htmlProvider              = htmlProvider
        context.coordinator.asciiProvider             = asciiProvider
        context.coordinator.spellingCompletionProvider = spellingCompletionProvider

        configureTypography(textView)
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Trigger ruler redraw when the view model changes (e.g. on content reload).
        nsView.verticalRulerView?.needsDisplay = true
    }

    // MARK: - Typography defaults

    private func configureTypography(_ textView: NSTextView) {
        textView.font            = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText      = false
        textView.allowsUndo      = true
        // Disable built-in auto-corrections — module 3.5 owns spelling/grammar.
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled  = false
        textView.isAutomaticDashSubstitutionEnabled   = false
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, NSTextViewDelegate {

        private let viewModel: EditorViewModel
        var textView:    EditorTextView?
        var ghostOverlay: GhostTextOverlay?
        var search:      SearchController?
        /// Strong reference keeps the checker alive for the view's lifetime (SW-2: the
        /// text view's reference is weak).
        var checker:     SpellingGrammarChecker?

        // Language providers — exactly one is dispatched per text change, based on mode.
        var markdownProvider:           MarkdownLanguageProvider?
        var htmlProvider:               HTMLLanguageProvider?
        var asciiProvider:              ASCIIArtLanguageProvider?
        var spellingCompletionProvider: SpellingCompletionProvider?

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        public func textDidChange(_ notification: Notification) {
            viewModel.isDirty = true
            // Debounced spelling/grammar re-check (no-op when spellCheckActive is false).
            checker?.onTextChange()
            // Dispatch to the active language provider for ghost-text completions.
            dispatchCompletionProvider()
            // Invalidate ruler on every edit so line numbers stay current.
            if let tv = notification.object as? NSTextView {
                tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            }
        }

        private func dispatchCompletionProvider() {
            switch viewModel.mode {
            case .markdown:  markdownProvider?.onKeypress()
            case .html:      htmlProvider?.onKeypress()
            case .asciiArt:  asciiProvider?.onKeypress()
            case .plainText: spellingCompletionProvider?.onKeypress()
            }
        }
    }
}
