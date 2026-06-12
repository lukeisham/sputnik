import AppKit
import FoundationModule
import ResourcesModule
import SputnikShared
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
    var isEditable: Bool

    public init(
        viewModel: EditorViewModel,
        settings: SettingsStore,
        appState: AppState,
        isEditable: Bool = true
    ) {
        self.viewModel = viewModel
        self.settings = settings
        self.appState = appState
        self.isEditable = isEditable
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // Build a standard scrollable text view, then swap the document view for
        // our EditorTextView subclass so key-event hooks are available.
        let scrollView = NSTextView.scrollableTextView()
        let textView = EditorTextView(frame: .zero)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        // Attach line-number ruler.
        let ruler = LineNumberRulerView(scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // Wire undo manager into the view model so sub-modules can post undo actions.
        viewModel.undoManager = textView.undoManager

        // Create shared overlay and search controller; inject into the text view.
        let overlay = GhostTextOverlay(textView: textView)
        let search = SearchController(textView: textView)
        textView.ghostTextOverlay = overlay
        textView.searchController = search

        // Spelling/grammar checker: held strongly by the coordinator (lives as long as the
        // view); the text view holds it weakly for click hit-testing (SW-2).
        let checker = SpellingGrammarChecker(
            textView: textView,
            viewModel: viewModel,
            settings: settings)
        textView.spellingChecker = checker
        textView.editorViewModel = viewModel
        textView.settings = settings

        // HTML structural checker: same lifetime/ownership model as the spelling checker
        // (coordinator holds it strongly, the text view weakly). Reads the spelling checker's
        // annotations so HTML underlines defer to overlapping spelling underlines.
        let htmlSyntaxChecker = HTMLSyntaxChecker(
            textView: textView,
            viewModel: viewModel,
            settings: settings,
            spellingChecker: checker)
        textView.htmlSyntaxChecker = htmlSyntaxChecker

        // Route "Look Up Help" through the Foundation help target (SR-1). Capture weakly
        // so the long-lived text view never retains AppState (SW-2).
        textView.onRequestHelp = { [weak appState] request in
            appState?.requestedHelpTarget = request
        }

        // Completion corpus — created once, shared across all four providers (SR-3).
        let corpus = SputnikCompletionCorpus()

        // Language providers — wired to the shared ghost overlay; one is active per mode.
        let blockCompletion = BlockCompletion()
        let markdownProvider = MarkdownLanguageProvider(
            textView: textView, ghostOverlay: overlay, settings: settings,
            completionProvider: corpus
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

        context.coordinator.textView = textView
        context.coordinator.ghostOverlay = overlay
        context.coordinator.search = search
        context.coordinator.checker = checker
        context.coordinator.htmlSyntaxChecker = htmlSyntaxChecker
        context.coordinator.markdownProvider = markdownProvider
        context.coordinator.htmlProvider = htmlProvider
        context.coordinator.asciiProvider = asciiProvider
        context.coordinator.spellingCompletionProvider = spellingCompletionProvider

        // Wire SearchController and TextView into the view model.
        viewModel.searchController = search
        viewModel.textView = textView

        // Set up syntax highlighting and debounce timer.
        if let storage = textView.textStorage {
            let highlighter = SyntaxHighlighter(textStorage: storage)
            highlighter.codeBlockHighlightEnabled = settings.codeBlockHighlightEnabled
            context.coordinator.syntaxHighlighter = highlighter
            context.coordinator.highlightDebounceTimer = DebounceTimer()
        }

        configureTypography(textView, settings: settings)
        textView.isEditable = isEditable

        // Publish the editor's scroll fraction for preview sync (ISS-063, Step 4).
        // The fraction (0=top, 1=bottom) is written to AppState.editorScrollFraction
        // so preview panels can follow the editor's scroll position.
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        let weakCoordinator = context.coordinator
        let weakAppState = appState
        context.coordinator.scrollObserverToken = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak weakCoordinator, weak scrollView, weak weakAppState] _ in
            guard let scrollView,
                let docView = scrollView.documentView,
                let coord = weakCoordinator
            else { return }
            let docH = docView.frame.height
            let viewH = scrollView.contentView.bounds.height
            guard docH > viewH else { return }
            let visibleY = scrollView.contentView.documentVisibleRect.origin.y
            let fraction = max(0.0, min(1.0, Double(visibleY / (docH - viewH))))
            guard abs(fraction - coord.lastPublishedFraction) > 0.005 else { return }
            coord.lastPublishedFraction = fraction
            weakAppState?.editorScrollFraction = fraction
        }

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Inject loaded text when loadToken changes (prevents re-applying stale content).
        if context.coordinator.lastAppliedLoadToken != viewModel.loadToken {
            context.coordinator.lastAppliedLoadToken = viewModel.loadToken
            textView.string = viewModel.loadedText
            textView.undoManager?.removeAllActions()

            // Run initial syntax highlight pass.
            if let storage = textView.textStorage {
                let highlighter = SyntaxHighlighter(textStorage: storage)
                highlighter.codeBlockHighlightEnabled = settings.codeBlockHighlightEnabled
                highlighter.highlight(mode: viewModel.mode)
            }
        }

        // Reapply font and background from settings (F-4) — settings may have changed
        // while the view was alive (e.g. per-panel override toggled in Preferences).
        applyFontAndBackground(textView, settings: settings)

        // Update isEditable in case the column role changed.
        textView.isEditable = isEditable

        // Propagate current-line highlight toggle (step 5).
        if let edTextView = textView as? EditorTextView {
            if edTextView.currentLineHighlightEnabled != settings.currentLineHighlightEnabled {
                edTextView.currentLineHighlightEnabled = settings.currentLineHighlightEnabled
                edTextView.needsDisplay = true
            }
        }

        // Propagate code-block highlighting toggle.
        if let highlighter = context.coordinator.syntaxHighlighter {
            if highlighter.codeBlockHighlightEnabled != settings.codeBlockHighlightEnabled {
                highlighter.codeBlockHighlightEnabled = settings.codeBlockHighlightEnabled
                // Trigger a re-highlight pass so the toggle takes effect immediately.
                highlighter.highlight(mode: viewModel.mode)
            }
        }

        // Wire the current-line highlight toggle into the line-number ruler (step 7).
        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.highlightCurrentLine = settings.currentLineHighlightEnabled
            ruler.needsDisplay = true
        }

        // Trigger ruler redraw when the view model changes (e.g. on content reload).
        nsView.verticalRulerView?.needsDisplay = true
    }

    // MARK: - Typography defaults

    /// Applies the resolved per-panel font and background colour to the text view.
    /// Called on initial creation and whenever `updateNSView` detects settings changes.
    private func configureTypography(_ textView: NSTextView, settings: SettingsStore) {
        applyFontAndBackground(textView, settings: settings)
        textView.isRichText = false
        textView.allowsUndo = true
        // Disable built-in auto-corrections — module 3.5 owns spelling/grammar.
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        // Opt into full Apple Intelligence Writing Tools on macOS 15+.
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }
    }

    /// Sets the font and background on the text view from the resolved settings (F-4).
    private func applyFontAndBackground(_ textView: NSTextView, settings: SettingsStore) {
        let editorFont = settings.resolvedTextEditorFont
        let font =
            NSFont(name: editorFont.postScriptName, size: editorFont.pointSize)
            ?? .monospacedSystemFont(ofSize: editorFont.pointSize, weight: .regular)
        textView.font = font
        textView.backgroundColor = NSColor(settings.textEditorBackground)
        textView.drawsBackground = true
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, NSTextViewDelegate {

        private let viewModel: EditorViewModel
        var textView: EditorTextView?
        var ghostOverlay: GhostTextOverlay?
        var search: SearchController?
        /// Strong reference keeps the checker alive for the view's lifetime (SW-2: the
        /// text view's reference is weak).
        var checker: SpellingGrammarChecker?
        /// Strong reference to the HTML structural checker (same ownership model as `checker`).
        var htmlSyntaxChecker: HTMLSyntaxChecker?

        // Track the last applied load token to prevent re-applying stale content.
        fileprivate var lastAppliedLoadToken: UUID?

        // Syntax highlighting
        fileprivate var syntaxHighlighter: SyntaxHighlighter?
        fileprivate var highlightDebounceTimer: DebounceTimer?

        // Editor scroll fraction observer for preview sync (ISS-063).
        var scrollObserverToken: NSObjectProtocol?
        fileprivate var lastPublishedFraction: Double = -1

        // Language providers — exactly one is dispatched per text change, based on mode.
        var markdownProvider: MarkdownLanguageProvider?
        var htmlProvider: HTMLLanguageProvider?
        var asciiProvider: ASCIIArtLanguageProvider?
        var spellingCompletionProvider: SpellingCompletionProvider?

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            // Only invalidate the affected rects to avoid a full redraw on every cursor
            // movement. Cache the old line rect and invalidate both old and new.
            let oldRect = tv.lastHighlightedLineRect
            tv.needsDisplay = true
            if let old = oldRect {
                tv.setNeedsDisplay(old, avoidAdditionalLayout: true)
            }
        }

        public func textDidChange(_ notification: Notification) {
            viewModel.isDirty = true

            // Debounced syntax highlighting with range-based re-highlight (ISS-057).
            // Extract the edited character range from the notification so the highlighter
            // only re-colours the affected region (plus a look-behind margin) instead of
            // the full document. Falls back to nil (full re-highlight) if the range is absent.
            let editedRange: NSRange? = (notification.userInfo?["NSRange"] as? NSValue)?.rangeValue
            let currentMode = viewModel.mode
            if currentMode != .plainText {
                highlightDebounceTimer?.cancel()
                highlightDebounceTimer?.schedule(delay: 0.3) { [weak self] in
                    self?.syntaxHighlighter?.highlight(mode: currentMode, editedRange: editedRange)
                }
            }

            // Debounced spelling/grammar re-check (no-op when spellCheckActive is false).
            checker?.onTextChange()
            // Debounced HTML structural re-check (no-op unless htmlModeActive + enabled).
            htmlSyntaxChecker?.onTextChange()
            // Dispatch to the active language provider for ghost-text completions.
            dispatchCompletionProvider()
            // Invalidate ruler on every edit so line numbers stay current.
            if let tv = notification.object as? NSTextView {
                tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            }

            // Schedule debounced crash recovery write (ISS-036, SR-4).
            if let textView = notification.object as? NSTextView {
                viewModel.scheduleRecoveryWrite(text: textView.string)
            }
        }

        @MainActor
        private func dispatchCompletionProvider() {
            switch viewModel.mode {
            case .markdown: markdownProvider?.onKeypress()
            case .html: htmlProvider?.onKeypress()
            case .asciiArt: asciiProvider?.onKeypress()
            case .plainText: spellingCompletionProvider?.onKeypress()
            }
        }
    }
}
