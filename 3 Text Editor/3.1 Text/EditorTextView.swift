import AppKit
import SwiftUI

/// The primary text-editing surface for Sputnik.
///
/// SW-3: raw AppKit (`NSTextView`) is justified here because it provides the ruler
/// attachment point, per-glyph layout access (`NSLayoutManager`), and `NSTextStorage`
/// mutation hooks that SwiftUI's `TextEditor` does not expose.
///
/// Key-event handling is kept minimal: Tab is intercepted for ghost-text acceptance,
/// ⌘F toggles the find bar, and all other keys clear the ghost text before normal
/// `NSTextView` handling. Presentation and layout stay in `EditorView` (SW-3 boundary).
public final class EditorTextView: NSTextView {

    // MARK: - Dependencies (weak — SW-2: avoid retain cycles on long-lived observers)

    /// The ghost-text overlay for this editing surface. Wired by `EditorView`.
    weak var ghostTextOverlay: GhostTextOverlay?

    /// The find/replace controller. Wired by `EditorView`.
    weak var searchController: SearchController?

    /// The spelling/grammar checker that owns the hit-testable annotation model (3.5).
    /// Wired by `EditorView`; used to map a click to an issue and its suggestions.
    weak var spellingChecker: SpellingGrammarChecker?

    /// The editor view model — read for the active mode when routing "Look Up Help".
    /// Wired by `EditorView`.
    weak var editorViewModel: EditorViewModel?

    /// The settings store — read to gate More Context items on `writingAssist.moreContext`.
    /// Wired by `EditorView`.
    weak var settings: SettingsStore?

    /// Sets the Foundation help target to reveal + navigate a help panel. Wired by
    /// `EditorView` so the AppKit text view never reaches into `AppState` directly.
    var onRequestHelp: ((HelpRequest) -> Void)?

    /// The shared help-context resolver that dispatches to module-9 coordinators.
    /// Wired by `EditorView`. Falls back to `SputnikHelpContextResolver.shared` when nil.
    var helpContextResolver: HelpContextResolving?

    /// The live quick-fix popover, if shown. AppKit seam for the SwiftUI `QuickfixPopover`.
    private var quickfixPopover: NSPopover?

    // MARK: - Key handling

    public override func keyDown(with event: NSEvent) {
        // Tab: give the ghost-text overlay first refusal.
        if event.keyCode == 48 {
            if let overlay = ghostTextOverlay, overlay.isVisible {
                overlay.accept()
                return
            }
        }

        // ⌘F: toggle the find bar.
        if event.modifierFlags.contains(.command),
            event.charactersIgnoringModifiers == "f"
        {
            searchController?.toggleVisible()
            return
        }

        // All other keys: clear ghost text, then proceed with normal AppKit handling.
        ghostTextOverlay?.clear()
        super.keyDown(with: event)
    }

    // MARK: - Click-to-fix (3.5)

    /// On a plain single click that lands on a rendered spelling/grammar underline, present
    /// the quick-fix popover. Otherwise fall through to normal `NSTextView` behaviour, so
    /// caret placement, selection, and drag are untouched (SW-3 seam documented here).
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        guard event.clickCount == 1,
            selectedRange().length == 0,
            let checker = spellingChecker,
            let layoutManager,
            let textContainer
        else { return }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard let annotation = checker.annotation(at: charIndex) else {
            quickfixPopover?.close()
            return
        }

        presentQuickfix(for: annotation, layoutManager: layoutManager, textContainer: textContainer)
    }

    private func presentQuickfix(
        for annotation: GrammarAnnotation,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        quickfixPopover?.close()

        // Anchor to the underlined range's bounding rect, in view coordinates.
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: annotation.range,
            actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let label = annotation.kind == .spelling ? "Spelling" : "Grammar"
        let view = QuickfixPopover(
            kindLabel: label,
            suggestions: annotation.suggestions,
            onFix: { [weak self] suggestion in self?.applyFix(annotation, suggestion: suggestion) },
            onDismiss: { [weak self] in self?.dismissAnnotation(annotation) }
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: view)
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        quickfixPopover = popover
    }

    private func applyFix(_ annotation: GrammarAnnotation, suggestion: String) {
        quickfixPopover?.close()
        guard let storage = textStorage else { return }
        let range = annotation.range
        // No-op on a stale range after a concurrent edit (SR-2, matches QuickfixPresenter).
        guard range.location != NSNotFound,
            range.location + range.length <= storage.length
        else { return }

        storage.replaceCharacters(in: range, with: suggestion)
        didChangeText()  // notify the delegate → debounced re-check
        spellingChecker?.recheckNow()  // and refresh underlines immediately
    }

    private func dismissAnnotation(_ annotation: GrammarAnnotation) {
        quickfixPopover?.close()
        // Ignore + re-check: clears this underline and surfaces any grammar issue the
        // dismissed spelling word was suppressing.
        spellingChecker?.dismiss(annotation)
    }

    // MARK: - Right-click More Context (3.5 / module 9 / shared utility)

    /// Appends "More Context: …" menu items for the active editor mode's help panel
    /// when there is a non-empty selection. Uses the shared `MoreContextMenu` builder
    /// and the injected (or fallback shared) resolver.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        let selection = selectedRange()
        guard selection.length > 0,
            let viewModel = editorViewModel,
            let kind = helpKind(for: viewModel)
        else { return menu }

        // Gate on the writingAssist matrix — non-applicable or disabled cells skip items.
        if let lang = assistLanguage(for: kind),
           settings?.writingAssist.isEnabled(.moreContext, for: lang) == false {
            return menu
        }

        let selected = (string as NSString).substring(with: selection)

        let resolver = helpContextResolver ?? SputnikHelpContextResolver.shared

        let moreItems = MoreContextMenu.items(
            forSelectedText: selected,
            kinds: [kind],
            fullText: string,
            cursorOffset: selection.location,
            resolver: resolver,
            onRequest: { [weak self] request in
                if let request = request {
                    self?.onRequestHelp?(request)
                }
            }
        )

        guard !moreItems.isEmpty else { return menu }

        menu.insertItem(.separator(), at: 0)
        for item in moreItems.reversed() {
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    /// Maps the active editor mode (and HTML gating) to its help panel, or `nil` when no
    /// help is appropriate. Grammar is always available in plain text.
    private func helpKind(for viewModel: EditorViewModel) -> HelpTopic? {
        switch viewModel.mode {
        case .plainText: return viewModel.htmlModeActive ? .html : .grammar
        case .markdown: return .markdown
        case .html: return .html
        case .asciiArt: return .asciiArt
        }
    }

    /// Maps a `HelpTopic` to its `WritingAssistLanguage` for the More Context gate.
    /// Returns `nil` for topics that have no matrix entry (e.g. `.sputnik`).
    private func assistLanguage(for kind: HelpTopic) -> WritingAssistLanguage? {
        switch kind {
        case .markdown: return .markdown
        case .html:     return .html
        case .grammar:  return .grammar
        case .asciiArt: return .asciiArt
        case .sputnik:  return nil
        }
    }

}
