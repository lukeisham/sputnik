import AppKit
import FoundationModule
import ResourcesModule
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

    /// The HTML structural checker (3.4). Wired by `EditorView`; used to map a click to an
    /// issue and its message.
    weak var htmlSyntaxChecker: HTMLSyntaxChecker?

    /// The editor view model — read for the active mode when routing "Look Up Help".
    /// Wired by `EditorView`.
    weak var editorViewModel: EditorViewModel?

    /// The settings store — read to gate More Context items on `writingAssist.moreContext`.
    /// Wired by `EditorView`.
    weak var settings: SettingsStore?

    /// Whether the current-line highlight is enabled. Set by `EditorView.updateNSView`.
    var currentLineHighlightEnabled: Bool = true

    /// Whether vertical indentation guide lines are enabled. Set by `EditorView.updateNSView`.
    var indentGuidesEnabled: Bool = false

    /// Sets the Foundation help target to reveal + navigate a help panel. Wired by
    /// `EditorView` so the AppKit text view never reaches into `AppState` directly.
    var onRequestHelp: ((HelpRequest) -> Void)?

    /// The shared help-context resolver that dispatches to module-9 coordinators.
    /// Wired by `EditorView`. Falls back to `SputnikHelpContextResolver.shared` when nil.
    var helpContextResolver: HelpContextResolving?

    /// The interaction coordinator for special-element detection and auto-fill.
    var interactionCoordinator: InteractionCoordinator?

    /// The live quick-fix popover, if shown. AppKit seam for the SwiftUI `QuickfixPopover`.
    private var quickfixPopover: NSPopover?

    /// The live summary popover, if shown. AppKit seam for the SwiftUI summary view.
    private var summaryPopover: NSPopover?

    // MARK: - First-responder tracking (ISS-118)

    /// Notifies `ASCIIStudioCoordinator` so it can track which editor last held focus.
    /// Required because the Studio panel's SwiftUI controls steal key-window first-responder
    /// when the user interacts with them, making `activeTextView()` return nil without this.
    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            NotificationCenter.default.post(
                name: Notification.Name("EditorTextViewDidBecomeFirstResponder"),
                object: self
            )
        }
        return result
    }

    // MARK: - Selection change (for Interaction detection)

    func setupSelectionChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textSelectionDidChange),
            name: NSTextView.didChangeSelectionNotification,
            object: self
        )
    }

    @objc private func textSelectionDidChange() {
        // Update interaction detection for the Edit menu "Interact with" item.
        guard let coordinator = interactionCoordinator,
            let viewModel = editorViewModel
        else { return }

        let range = selectedRange()
        coordinator.updateDetection(
            text: string,
            selectedRange: range,
            language: viewModel.interactionLanguage
        )
    }

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

    // MARK: - Click-to-fix (HTML structural issues)

    /// On a plain single click that lands on a rendered HTML structural underline, present
    /// the quick-fix popover. Apple's spelling and grammar underlines use their own
    /// right-click menu, so they do not come here. Otherwise fall through to normal `NSTextView` behaviour, so
    /// caret placement, selection, and drag are untouched (SW-3 seam documented here).
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        guard event.clickCount == 1,
            selectedRange().length == 0,
            let layoutManager,
            let textContainer
        else { return }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard let annotation = htmlSyntaxChecker?.annotation(at: charIndex) else {
            quickfixPopover?.close()
            return
        }

        presentQuickfix(for: annotation, layoutManager: layoutManager, textContainer: textContainer)
    }

    private func presentQuickfix(
        for annotation: EditorAnnotation,
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

        let label: String
        let suggestions: [String]
        switch annotation.kind {
        case .htmlSyntax:
            // The HTML checker carries a descriptive message, not a replacement string, so
            // surface it in the header and offer only Dismiss (no auto-fix for structure).
            label = "HTML — \(annotation.suggestions.first ?? "Structural issue")"
            suggestions = []
        }
        let view = QuickfixPopover(
            kindLabel: label,
            suggestions: suggestions,
            onFix: { [weak self] suggestion in self?.applyFix(annotation, suggestion: suggestion) },
            onDismiss: { [weak self] in self?.dismissAnnotation(annotation) }
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: view)
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        quickfixPopover = popover
    }

    private func applyFix(_ annotation: EditorAnnotation, suggestion: String) {
        quickfixPopover?.close()
        guard let storage = textStorage else { return }
        let range = annotation.range
        // No-op on a stale range after a concurrent edit (SR-2, matches QuickfixPresenter).
        guard range.location != NSNotFound,
            range.location + range.length <= storage.length
        else { return }

        storage.replaceCharacters(in: range, with: suggestion)
        didChangeText()  // notify the delegate → debounced re-check
        htmlSyntaxChecker?.recheckNow()  // and refresh underlines immediately
    }

    private func dismissAnnotation(_ annotation: EditorAnnotation) {
        quickfixPopover?.close()
        // Ignore + re-check: clears this underline.
        switch annotation.kind {
        case .htmlSyntax:
            htmlSyntaxChecker?.dismiss(annotation)
        }
    }

    // MARK: - Current-line highlight

    /// The line fragment rect of the last drawn current-line highlight, in view coordinates.
    /// Cached so we can invalidate only the old rect on cursor movement (step 4).
    /// `internal` (not private) so `EditorView.Coordinator` can read it for invalidation.
    var lastHighlightedLineRect: NSRect?

    /// Draws a subtle highlight behind the line containing the insertion point.
    ///
    /// Called by AppKit during the display pass. When `currentLineHighlightEnabled` is true,
    /// we use `NSLayoutManager` to find the line fragment rect for the current glyph index
    /// and fill it with a semi-transparent accent colour. The colour is derived from
    /// `selectedTextBackgroundColor` which adapts to light/dark mode automatically.
    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard currentLineHighlightEnabled,
            let layoutMgr = layoutManager
        else {
            lastHighlightedLineRect = nil
            return
        }

        let insertionIndex = selectedRange().location
        guard insertionIndex != NSNotFound else { return }

        let glyphIndex = layoutMgr.glyphIndexForCharacter(at: insertionIndex)
        var fragRect = layoutMgr.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        // Clamp to the visible rect to avoid drawing off-screen areas.
        fragRect = rect.intersection(fragRect)
        guard !fragRect.isNull, !fragRect.isInfinite else { return }

        let highlightColour = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12)
        highlightColour.setFill()
        fragRect.fill()

        lastHighlightedLineRect = fragRect

        // Draw vertical indentation guides after the current-line highlight (step 3).
        drawIndentGuides(in: rect)
    }

    // MARK: - Indentation guides

    /// Draws thin vertical guide lines at each indentation level for visible line fragments.
    /// Runs in the display pass after the current-line highlight. Guides clip to the dirty
    /// `rect` and use a low-alpha separator-adaptive colour so they stay subtle in both
    /// light and dark modes. Word-wrapped continuation lines only draw guides for their
    /// own leading whitespace, never restarting the indent count.
    private func drawIndentGuides(in rect: NSRect) {
        guard indentGuidesEnabled,
            let layoutMgr = layoutManager,
            let textContainer = textContainer,
            let font = self.font
        else { return }

        let origin = textContainerOrigin
        let indentSize = 4  // standard editor indent width in columns

        // Measure the width of one column (a space character) using the current font.
        let spaceStr = NSAttributedString(string: " ", attributes: [.font: font])
        let columnWidth = spaceStr.size().width
        guard columnWidth > 0 else { return }
        let indentWidth = columnWidth * CGFloat(indentSize)

        let guideColour = (self.textColor ?? NSColor.textColor).withAlphaComponent(0.10)

        // Find the glyph range that intersects the dirty rect so we only visit visible lines.
        let glyphRange = layoutMgr.glyphRange(
            forBoundingRect: rect.offsetBy(
                dx: -origin.x, dy: -origin.y), in: textContainer)
        guard glyphRange.length > 0 else { return }

        var glyphIndex = glyphRange.location
        let endGlyph = NSMaxRange(glyphRange)

        while glyphIndex < endGlyph {
            var fragRange: NSRange = NSRange(location: 0, length: 0)
            let fragRectRaw = layoutMgr.lineFragmentRect(
                forGlyphAt: glyphIndex, effectiveRange: &fragRange)
            let fragRect = fragRectRaw.offsetBy(dx: origin.x, dy: origin.y)
            glyphIndex = NSMaxRange(fragRange)

            // Clip to the dirty rect.
            let clipped = rect.intersection(fragRect)
            guard !clipped.isNull, !clipped.isInfinite else { continue }

            // Get the text for this line fragment to measure leading whitespace.
            let charRange = layoutMgr.characterRange(
                forGlyphRange: fragRange, actualGlyphRange: nil)
            guard charRange.length > 0,
                let textStorage = textStorage
            else { continue }

            let lineText = (textStorage.string as NSString).substring(with: charRange)
            let leading = leadingWhitespaceWidth(
                lineText, columnWidth: columnWidth, indentSize: indentSize)
            guard leading.spaces > 0 else { continue }

            // Draw one guide per indent level.
            for level in 1...leading.spaces {
                let x = origin.x + indentWidth * CGFloat(level) - 0.5
                let guideRect = NSRect(
                    x: x, y: clipped.minY,
                    width: 1, height: clipped.height)
                guideColour.setFill()
                guideRect.fill()
            }
        }
    }

    /// Returns the number of indent levels in a line's leading whitespace.
    ///
    /// - For tab-indented lines, each tab is one level.
    /// - For space-indented lines, every `indentSize` spaces is one level.
    /// - Mixed leading whitespace uses the first character type encountered.
    private func leadingWhitespaceWidth(
        _ line: String, columnWidth _: CGFloat, indentSize: Int
    ) -> (spaces: Int, tabs: Int) {
        var spaceCount = 0
        var tabCount = 0
        var sawTab = false
        for ch in line {
            if ch == "\t" {
                sawTab = true
                tabCount += 1
            } else if ch == " " {
                if sawTab { break }  // mixed: stop at first non-tab after tabs
                spaceCount += 1
            } else {
                break
            }
        }
        if tabCount > 0 {
            return (spaces: tabCount, tabs: tabCount)
        }
        return (spaces: spaceCount / indentSize, tabs: 0)
    }

    // MARK: - Right-click More Context (module 9 / shared utility)

    /// Appends "More Context: …" menu items for the active editor mode's help panel
    /// when there is a non-empty selection. Uses the shared `MoreContextMenu` builder
    /// and the injected (or fallback shared) resolver.
    /// Also appends "Summarize Locally" on macOS 15+ using on-device NLSummarizer.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        let selection = selectedRange()
        // Apple's spelling suggestions stay at the top of the menu (see `sputnikItemIndex`).
        let base = sputnikItemIndex(in: menu, selection: selection)

        // Add "Summarize Locally" when there is a non-empty selection.
        if selection.length > 0 {
            let summarizeItem = NSMenuItem(
                title: "Summarize Locally",
                action: #selector(summarizeSelectionLocally),
                keyEquivalent: "")
            summarizeItem.target = self
            menu.insertItem(summarizeItem, at: base)
            menu.insertItem(.separator(), at: base + 1)
        }

        guard selection.length > 0,
            let viewModel = editorViewModel,
            let kind = helpKind(for: viewModel)
        else { return menu }

        // Gate on the writingAssist matrix — non-applicable or disabled cells skip items.
        if let lang = assistLanguage(for: kind),
            settings?.writingAssist.isEnabled(.moreContext, for: lang) == false
        {
            return menu
        }

        let selected = (string as NSString).substring(with: selection)

        // ASCII Art uses a level-based submenu; all other kinds use the flat resolver.
        if kind == .asciiArt {
            let asciiSubmenu = NSMenu(title: "")

            let basicItem = ClosureMenuItem(title: "Basic") { [weak self] in
                Task { @MainActor in
                    let topic = await ASCIIArtHelpCoordinator.shared.bestMatch(
                        for: selected, level: .basic)
                    if let topic, let request = self?.onRequestHelp {
                        request(HelpRequest(kind: .asciiArt, topicID: topic.id))
                    }
                }
            }

            let advancedItem = ClosureMenuItem(title: "Advanced") { [weak self] in
                Task { @MainActor in
                    let topic = await ASCIIArtHelpCoordinator.shared.bestMatch(
                        for: selected, level: .advanced)
                    if let topic, let request = self?.onRequestHelp {
                        request(HelpRequest(kind: .asciiArt, topicID: topic.id))
                    }
                }
            }

            asciiSubmenu.addItem(basicItem)
            asciiSubmenu.addItem(advancedItem)

            let parentItem = NSMenuItem(
                title: "More Context: ASCII Art",
                action: nil, keyEquivalent: "")
            parentItem.submenu = asciiSubmenu

            menu.insertItem(.separator(), at: base)
            menu.insertItem(parentItem, at: base)
            return menu
        }

        let resolver = helpContextResolver ?? SputnikHelpContextResolver.shared

        // Gate on the writingAssist matrix — check both Interaction and MoreContext.
        let interactionEnabled: Bool
        if let lang = assistLanguage(for: kind) {
            interactionEnabled = settings?.writingAssist.isEnabled(.interaction, for: lang) ?? false
        } else {
            interactionEnabled = false
        }

        // Use SelectionContextMenu which handles Interaction-vs-More-Context precedence.
        let lang = viewModel.interactionLanguage
        let contextItems = SelectionContextMenu.items(
            forSelectedText: selected,
            fullText: string,
            cursorOffset: selection.location,
            selectionLength: selection.length,
            language: lang,
            detector: interactionCoordinator?.detector ?? SpecialElementDetector(),
            interactionEnabled: interactionEnabled,
            moreContextKinds: [kind],
            resolver: resolver,
            onInteract: { [weak self] element in
                guard let self, let coordinator = self.interactionCoordinator else { return }
                let selectionRect = self.selectionRectForPopover()
                coordinator.trigger(
                    relativeTo: selectionRect,
                    in: self,
                    selectedText: selected,
                    fullText: self.string,
                    language: lang
                ) { [weak self] newText, range in
                    guard let self else { return }
                    if self.shouldChangeText(in: range, replacementString: newText) {
                        self.replaceCharacters(in: range, with: newText)
                        self.didChangeText()
                    }
                }
            },
            onMoreContext: { [weak self] request in
                if let request = request {
                    self?.onRequestHelp?(request)
                }
            }
        )

        guard !contextItems.isEmpty else { return menu }

        menu.insertItem(.separator(), at: base)
        for item in contextItems.reversed() {
            menu.insertItem(item, at: base)
        }
        return menu
    }

    /// Returns the menu index where Sputnik items go.
    ///
    /// When the selection is a misspelled word, Apple puts its spelling suggestions at the
    /// top of the menu, followed by a separator. In that case, Sputnik items go after that
    /// separator so Apple's suggestions stay first. In all other cases, the index is 0.
    private func sputnikItemIndex(in menu: NSMenu, selection: NSRange) -> Int {
        // Only a short selection can be a single misspelled word. This also keeps the
        // check fast on large selections (SR-4).
        guard isContinuousSpellCheckingEnabled,
            selection.length > 0, selection.length <= 64,
            selection.location + selection.length <= (string as NSString).length
        else { return 0 }
        let word = (string as NSString).substring(with: selection)
        let misspelled = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: nil, wrap: false,
            inSpellDocumentWithTag: spellCheckerDocumentTag, wordCount: nil)
        guard misspelled.location != NSNotFound,
            let separator = menu.items.firstIndex(where: \.isSeparatorItem)
        else { return 0 }
        return separator + 1
    }

    /// Maps the active editor mode (and HTML gating) to its help panel, or `nil` when no
    /// help is appropriate. Style help is always available in plain text.
    private func helpKind(for viewModel: EditorViewModel) -> HelpTopic? {
        switch viewModel.mode {
        case .plainText: return viewModel.htmlModeActive ? .html : .style
        case .markdown: return .markdown
        case .html: return .html
        case .json: return .json
        case .asciiArt: return .asciiArt
        }
    }

    /// Maps a `HelpTopic` to its `WritingAssistLanguage` for the More Context gate.
    /// Returns `nil` for topics that have no matrix entry (e.g. `.sputnik`).
    private func assistLanguage(for kind: HelpTopic) -> WritingAssistLanguage? {
        switch kind {
        case .markdown: return .markdown
        case .html: return .html
        case .json: return .json
        case .style: return .style
        case .asciiArt: return .asciiArt
        case .sputnik: return nil
        }
    }

    // MARK: - On-Device Summarization (macOS 15+)

    /// Summarises the current text selection using on-device natural language processing.
    /// Uses extractive sentence scoring via term frequency to select key sentences.
    /// Presents the result in a transient popover anchored to the selection.
    @objc private func summarizeSelectionLocally() {
        let selection = selectedRange()
        guard selection.length > 0 else { return }

        summaryPopover?.close()

        let selected = (string as NSString).substring(with: selection)

        // Show a loading indicator while the summary is computed.
        let loadingView = NSHostingController(
            rootView: SummaryPopoverContent(text: "Summarizing…", isLoading: true))
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = loadingView
        popover.show(relativeTo: selectionRectForPopover(), of: self, preferredEdge: .maxY)
        summaryPopover = popover

        Task { @MainActor in
            let summary = Self.extractiveSummary(of: selected, maxSentences: 3)
            let resultView = NSHostingController(
                rootView: SummaryPopoverContent(text: summary, isLoading: false))
            popover.contentViewController = resultView
        }
    }

    /// Performs extractive summarization via `ExtractiveSummarizer` (extracted to its own
    /// type per SR-6; see `ExtractiveSummarizer.swift` and ISS-137).
    private static func extractiveSummary(of text: String, maxSentences: Int) -> String {
        ExtractiveSummarizer.summary(of: text, maxSentences: maxSentences)
    }

    /// Returns the bounding rect of the current selection in view coordinates,
    /// used as the anchor rect for the summary popover.
    private func selectionRectForPopover() -> NSRect {
        guard let layoutManager, let textContainer else {
            return bounds
        }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: selectedRange(), actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return bounds }
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    // MARK: - Drag and drop (image files)

    /// Validates that the dragging pasteboard contains image file URLs.
    /// Accepts the drag with `.copy` operation if so.
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if ImageDropMarkupBuilder.hasImageFileURL(in: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    /// Continues accepting image file URL drags with `.copy`.
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if ImageDropMarkupBuilder.hasImageFileURL(in: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    /// Handles a drop containing an image file URL:
    /// 1. Opens the image in the PDF Viewer via the router.
    /// 2. Inserts Markdown/HTML markup at the drop point.
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let fileURL = ImageDropMarkupBuilder.imageFileURL(from: sender.draggingPasteboard)
        else {
            return super.performDragOperation(sender)
        }

        // Open the image in the PDF Viewer.
        if let router = editorViewModel?.router {
            Task { @MainActor in
                await router.open(fileURL)
            }
        }

        // Compute relative path for markup insertion.
        let markup = ImageDropMarkupBuilder.markupString(
            for: fileURL,
            mode: editorViewModel?.mode ?? .plainText,
            editorFileURL: editorViewModel?.fileURL)
        insertText(markup, replacementRange: selectedRange())

        return true
    }

}
