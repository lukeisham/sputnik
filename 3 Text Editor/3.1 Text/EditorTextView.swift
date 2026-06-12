import AppKit
import FoundationModule
import NaturalLanguage
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

    /// The spelling/grammar checker that owns the hit-testable annotation model (3.5).
    /// Wired by `EditorView`; used to map a click to an issue and its suggestions.
    weak var spellingChecker: SpellingGrammarChecker?

    /// The HTML structural checker (3.4). Wired by `EditorView`; queried as a fallback when
    /// the spelling checker has no annotation at the clicked location.
    weak var htmlSyntaxChecker: HTMLSyntaxChecker?

    /// The editor view model — read for the active mode when routing "Look Up Help".
    /// Wired by `EditorView`.
    weak var editorViewModel: EditorViewModel?

    /// The settings store — read to gate More Context items on `writingAssist.moreContext`.
    /// Wired by `EditorView`.
    weak var settings: SettingsStore?

    /// Whether the current-line highlight is enabled. Set by `EditorView.updateNSView`.
    var currentLineHighlightEnabled: Bool = true

    /// Sets the Foundation help target to reveal + navigate a help panel. Wired by
    /// `EditorView` so the AppKit text view never reaches into `AppState` directly.
    var onRequestHelp: ((HelpRequest) -> Void)?

    /// The shared help-context resolver that dispatches to module-9 coordinators.
    /// Wired by `EditorView`. Falls back to `SputnikHelpContextResolver.shared` when nil.
    var helpContextResolver: HelpContextResolving?

    /// The live quick-fix popover, if shown. AppKit seam for the SwiftUI `QuickfixPopover`.
    private var quickfixPopover: NSPopover?

    /// The live summary popover, if shown. AppKit seam for the SwiftUI summary view.
    private var summaryPopover: NSPopover?

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
            let layoutManager,
            let textContainer
        else { return }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        // Spelling/grammar takes priority; fall back to an HTML structural underline.
        guard let annotation = spellingChecker?.annotation(at: charIndex)
            ?? htmlSyntaxChecker?.annotation(at: charIndex)
        else {
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

        let label: String
        let suggestions: [String]
        switch annotation.kind {
        case .spelling:
            label = "Spelling"
            suggestions = annotation.suggestions
        case .grammar:
            label = "Grammar"
            suggestions = annotation.suggestions
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
        // dismissed spelling word was suppressing. Route HTML issues to their own checker.
        switch annotation.kind {
        case .spelling, .grammar:
            spellingChecker?.dismiss(annotation)
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
    }

    // MARK: - Right-click More Context (3.5 / module 9 / shared utility)

    /// Appends "More Context: …" menu items for the active editor mode's help panel
    /// when there is a non-empty selection. Uses the shared `MoreContextMenu` builder
    /// and the injected (or fallback shared) resolver.
    /// Also appends "Summarize Locally" on macOS 15+ using on-device NLSummarizer.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        let selection = selectedRange()

        // Add "Summarize Locally" when there is a non-empty selection.
        if selection.length > 0 {
            let summarizeItem = NSMenuItem(
                title: "Summarize Locally",
                action: #selector(summarizeSelectionLocally),
                keyEquivalent: "")
            summarizeItem.target = self
            menu.insertItem(summarizeItem, at: 0)
            menu.insertItem(.separator(), at: 1)
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

            menu.insertItem(.separator(), at: 0)
            menu.insertItem(parentItem, at: 0)
            return menu
        }

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
        case .html: return .html
        case .grammar: return .grammar
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

    /// Performs extractive summarization using NLTokenizer for sentence segmentation
    /// and TF-based sentence scoring. Fully on-device — no network, no API key.
    private static func extractiveSummary(of text: String, maxSentences: Int) -> String {
        guard !text.isEmpty else {
            return "No text selected."
        }

        // Tokenize into sentences using NaturalLanguage.
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex).map {
            String(text[$0])
        }

        guard sentences.count > 1 else {
            // Single sentence — return it truncated.
            return sentences.first.map { $0.count > 280 ? String($0.prefix(277)) + "…" : $0 }
                ?? text
        }

        // Build term-frequency map (lowercased, non-trivial words).
        var termFreq: [String: Int] = [:]
        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = text
        wordTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            // Skip short words and stop words.
            if word.count > 3 {
                termFreq[word, default: 0] += 1
            }
            return true
        }

        // Score each sentence by summed term frequency (normalized by sentence length).
        struct ScoredSentence {
            let text: String
            let score: Double
        }
        var scored: [ScoredSentence] = []
        for sentence in sentences {
            let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let words = cleaned.split(separator: " ").map(String.init)
            guard words.count >= 4 else { continue }  // Skip very short fragments.
            let totalScore = words.reduce(0.0) { score, word in
                score + Double(termFreq[word.lowercased(), default: 0])
            }
            let normalized = totalScore / Double(max(words.count, 1))
            scored.append(ScoredSentence(text: cleaned, score: normalized))
        }

        // Sort by score descending, take top N, re-sort by original position.
        let top = scored.sorted { $0.score > $1.score }.prefix(maxSentences)
        let result = top.sorted {
            sentences.firstIndex(of: $0.text)! < sentences.firstIndex(of: $1.text)!
        }
        .map { $0.text }
        .joined(separator: "\n\n")

        return result.isEmpty ? "(Unable to generate summary.)" : result
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
        if hasImageFileURL(in: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    /// Continues accepting image file URL drags with `.copy`.
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImageFileURL(in: sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    /// Handles a drop containing an image file URL:
    /// 1. Opens the image in the PDF Viewer via the router.
    /// 2. Inserts Markdown/HTML markup at the drop point.
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let fileURL = imageFileURL(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }

        // Open the image in the PDF Viewer.
        if let router = editorViewModel?.router {
            Task { @MainActor in
                await router.open(fileURL)
            }
        }

        // Compute relative path for markup insertion.
        let markup = markupString(for: fileURL)
        insertText(markup, replacementRange: selectedRange())

        return true
    }

    /// Checks if the pasteboard contains an image file URL.
    private func hasImageFileURL(in pasteboard: NSPasteboard) -> Bool {
        imageFileURL(from: pasteboard) != nil
    }

    /// Extracts the first image file URL from the pasteboard, if any.
    private func imageFileURL(from pasteboard: NSPasteboard) -> URL? {
        guard let items = pasteboard.pasteboardItems else { return nil }
        for item in items {
            guard let urlString = item.string(forType: .fileURL),
                let url = URL(string: urlString)
            else { continue }
            // Normalise the file URL.
            let fileURL = if url.isFileURL { url } else { URL(fileURLWithPath: url.path) }
            guard fileURL.isFileURL else { continue }
            let ext = fileURL.pathExtension.lowercased()
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "bmp", "tiff"]
            if imageExtensions.contains(ext) {
                return fileURL
            }
        }
        return nil
    }

    /// Computes the markup string to insert for the given image file URL.
    /// Uses Markdown syntax `![filename](path)` for `.markdown` mode and
    /// HTML `<img src="path" alt="filename">` for `.html` mode.
    /// Falls back to Markdown for all other modes.
    private func markupString(for imageURL: URL) -> String {
        let useHTML = editorViewModel?.mode == .html
        let filename = imageURL.deletingPathExtension().lastPathComponent
        let path = relativePath(for: imageURL)

        if useHTML {
            let escapedPath =
                path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
            let escapedAlt =
                filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
            return "<img src=\"\(escapedPath)\" alt=\"\(escapedAlt)\">"
        } else {
            // Markdown syntax (default fallback)
            return "![\(filename)](\(path))"
        }
    }

    /// Computes a relative path from the editor's current file directory to `imageURL`.
    /// Falls back to the absolute path when no editor file is open.
    private func relativePath(for imageURL: URL) -> String {
        guard let editorFileURL = editorViewModel?.fileURL else {
            return imageURL.path
        }
        let editorDir = editorFileURL.deletingLastPathComponent()
        let imagePath = imageURL.resolvingSymlinksInPath().path
        let dirPath = editorDir.resolvingSymlinksInPath().path

        guard imagePath.hasPrefix(dirPath) else {
            // Image is outside the editor's directory tree — use absolute path.
            return imageURL.path
        }

        var relative = String(imagePath.dropFirst(dirPath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return relative.isEmpty ? imageURL.lastPathComponent : relative
    }

}

// MARK: - Summarization Popover View

/// A simple SwiftUI view for displaying a summary result (or loading/error state)
/// inside an NSPopover.
private struct SummaryPopoverContent: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 4)
            }
            Text(text)
                .textSelection(.enabled)
                .font(.system(size: 12))
                .padding(8)
                .frame(maxWidth: 280, alignment: .leading)
        }
        .padding(4)
    }
}
