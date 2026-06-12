import AppKit
import FoundationModule
import SwiftUI

/// AppKit bridge for the Markdown Preview — wraps an `NSTextView` in an
/// `NSViewRepresentable` for read-only, selectable, link-interactive display.
///
/// **AppKit bridge rationale (SW-3):** SwiftUI's built-in `Text` view does not support
/// text selection, clipboard copy (⌘C), or clickable link callbacks. `NSTextView`
/// provides all three natively and is the correct interop path for a Markdown viewer.
///
/// The text view is configured as read-only, non-editable, with link detection
/// disabled (links come from the `AttributedString`, not auto-detect), and a
/// comfortable text-container inset. Scroll is handled by a SwiftUI `ScrollView`
/// wrapping this view in `MarkdownPreviewPanel`.
public struct MarkdownRenderView: NSViewRepresentable {

    // MARK: - Input

    /// The rendered Markdown content to display (may contain `NSTextAttachment` images).
    let renderedString: NSAttributedString

    /// The current font-scale factor for the content.
    let fontScale: CGFloat

    /// The coordinator that handles link clicks.
    let coordinator: MarkdownPreviewCoordinator

    /// The settings store, read for per-panel font and background (F-4).
    let settings: SettingsStore

    /// Binding into the panel's per-document scroll-offset dictionary.
    /// The render view reads this to restore position after re-render and writes
    /// it whenever the user scrolls.
    let scrollOffset: Binding<CGFloat>

    /// Binding to a print-action closure. The view sets this in `updateNSView` so the
    /// parent panel can trigger a print of the Markdown content via `NSTextView`.
    @Binding var printAction: (() -> Void)?

    /// Binding to a save-as-PDF closure. The view sets this in `updateNSView` so the
    /// parent panel can trigger a PDF export of the Markdown content via `NSPrintOperation`.
    @Binding var saveAsPDFAction: (() -> Void)?

    /// Binding to a save-as-Markdown closure. The view sets this in `updateNSView` so the
    /// parent panel can export the active document's raw Markdown source to a `.md` file.
    @Binding var saveAsMarkdownAction: (() -> Void)?

    /// The fractional scroll position to apply for editor→preview sync (ISS-063, Step 5).
    /// `nil` when sync is disabled or the document exceeds the large-file threshold (Step 10).
    /// Range 0.0 (top) … 1.0 (bottom). Applied in `updateNSView` only when the fraction
    /// changes by more than 0.005 from the last applied value, to suppress feedback loops.
    let syncScrollFraction: Double?

    // MARK: - Init

    /// Creates the render view.
    ///
    /// - Parameters:
    ///   - renderedString: The parsed Markdown to display.
    ///   - fontScale:      Font zoom factor (1.0 = default).
    ///   - coordinator:    The link-click coordinator.
    ///   - settings:       The app settings store (for per-panel font/background).
    ///   - scrollOffset:   Binding for per-document scroll offset.
    ///   - printAction:          Binding set by the view with the print closure.
    ///   - saveAsPDFAction:       Binding set by the view with the save-as-PDF closure.
    ///   - saveAsMarkdownAction:  Binding set by the view with the save-as-Markdown closure.
    public init(
        renderedString: NSAttributedString,
        fontScale: CGFloat,
        coordinator: MarkdownPreviewCoordinator,
        settings: SettingsStore,
        scrollOffset: Binding<CGFloat> = .constant(0),
        syncScrollFraction: Double? = nil,
        printAction: Binding<(() -> Void)?> = .constant(nil),
        saveAsPDFAction: Binding<(() -> Void)?> = .constant(nil),
        saveAsMarkdownAction: Binding<(() -> Void)?> = .constant(nil)
    ) {
        self.renderedString = renderedString
        self.fontScale = fontScale
        self.coordinator = coordinator
        self.settings = settings
        self.scrollOffset = scrollOffset
        self.syncScrollFraction = syncScrollFraction
        _printAction = printAction
        _saveAsPDFAction = saveAsPDFAction
        _saveAsMarkdownAction = saveAsMarkdownAction
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> MarkdownPreviewCoordinator {
        coordinator
    }

    public func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)

        // Read-only, selectable display.
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false

        // Links come from the AttributedString, not auto-detection.
        textView.isAutomaticLinkDetectionEnabled = false

        // Appearance — use per-panel background (F-4).
        textView.backgroundColor = NSColor(settings.markdownPreviewBackground)
        textView.drawsBackground = true

        // Comfortable padding.
        textView.textContainerInset = NSSize(width: 16, height: 16)

        // Width tracks the text view so text wraps naturally.
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        // Disable the built-in scroll view — SwiftUI handles scrolling.
        textView.enclosingScrollView?.hasVerticalScroller = false
        textView.enclosingScrollView?.hasHorizontalScroller = false

        // Wire the delegate for link-click handling.
        textView.delegate = context.coordinator

        // ⌘-click gesture recognizer for bidirectional source navigation (ISS-065, Step 9).
        // The recognizer fires for all clicks; the handler checks for the ⌘ modifier key
        // and yields to the NSTextViewDelegate when the click lands on a link.
        let clickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(MarkdownPreviewCoordinator.handleCommandClick(_:))
        )
        clickRecognizer.numberOfClicksRequired = 1
        textView.addGestureRecognizer(clickRecognizer)

        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        // Reapply background from settings (F-4) — may have changed since last update.
        textView.backgroundColor = NSColor(settings.markdownPreviewBackground)

        // Keep the coordinator's binding pointing at the current document's slot so
        // the scroll observer always writes to the right entry in the panel's dict.
        context.coordinator.scrollOffsetBinding = scrollOffset

        // Apply editor→preview scroll sync (ISS-063, Step 5).
        // Only fires when sync is enabled (fraction is non-nil) and has moved enough
        // to be worth applying. Runs at +0.02 s, before the render's scroll-restore
        // at +0.05 s, so a re-render always wins (restores the user's saved position).
        if let fraction = syncScrollFraction,
            abs(fraction - context.coordinator.lastSyncScrollFraction) > 0.005
        {
            context.coordinator.lastSyncScrollFraction = fraction
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak textView] in
                guard let scrollView = textView?.enclosingScrollView else { return }
                let docH = scrollView.documentView?.frame.height ?? 0
                let viewH = scrollView.contentView.bounds.height
                guard docH > viewH else { return }
                let targetY = CGFloat(fraction) * (docH - viewH)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        // Set up (or re-set up) the scroll observer against the current clip view.
        // Re-registration is needed when fitWidth toggles rebuild the view tree and
        // the hosting NSScrollView changes.
        if let clipView = textView.enclosingScrollView?.contentView as? NSClipView,
            clipView !== context.coordinator.observedClipView
        {
            if let token = context.coordinator.scrollObserverToken {
                NotificationCenter.default.removeObserver(token)
            }
            clipView.postsBoundsChangedNotifications = true
            context.coordinator.observedClipView = clipView
            let weakCoordinator = context.coordinator
            context.coordinator.scrollObserverToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak weakCoordinator, weak textView] _ in
                MainActor.assumeIsolated {
                    guard let y = textView?.enclosingScrollView?.documentVisibleRect.origin.y else {
                        return
                    }
                    weakCoordinator?.scrollOffsetBinding?.wrappedValue = y
                }
            }
        }

        // Wire the print action so the panel's overflow menu can trigger printing.
        printAction = { [weak textView] in
            guard let textView, let window = textView.window else { return }
            let printOp = NSPrintOperation(view: textView, printInfo: .shared)
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }

        // Wire the save-as-Markdown action. Capture source text and document name
        // from the coordinator (set by the panel before each render) so the closure
        // is safe to call later without racing on the active document.
        let capturedSource = coordinator.currentSourceText
        let capturedName = coordinator.currentDocumentName
        saveAsMarkdownAction = { [weak textView] in
            guard let textView, let window = textView.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.text]  // .md has no UTType constant; .text opens the name field freely
            let baseName = (capturedName as NSString).deletingPathExtension
            panel.nameFieldStringValue = baseName.isEmpty ? "document.md" : baseName + ".md"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                Task(priority: .userInitiated) {
                    do {
                        try capturedSource.write(
                            to: url, atomically: true, encoding: .utf8)
                    } catch {
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.messageText = "Save as Markdown Failed"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.runModal()
                        }
                    }
                }
            }
        }

        // Wire the save-as-PDF action.
        saveAsPDFAction = { [weak textView] in
            guard let textView, let window = textView.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "document.pdf"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                let pdfRect = textView.bounds
                let pdfData = textView.dataWithPDF(inside: pdfRect)
                guard !pdfData.isEmpty else {
                    let alert = NSAlert()
                    alert.messageText = "PDF Generation Failed"
                    alert.informativeText = "Could not generate PDF data from the rendered content."
                    alert.alertStyle = .warning
                    alert.runModal()
                    return
                }
                do {
                    try pdfData.write(to: url)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Save as PDF Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }

        // Only update the text storage when the content has actually changed,
        // to avoid unnecessary layout invalidation.
        guard textView.textStorage?.string != renderedString.string else {
            return
        }

        // Capture the desired scroll offset before rewriting the text storage.
        let targetOffset = scrollOffset.wrappedValue

        // Use the resolved preview font as the base font, scaled by fontScale (F-4).
        let previewFont = settings.resolvedMarkdownPreviewFont
        let scaledSize = previewFont.pointSize * fontScale
        textView.font =
            NSFont(name: previewFont.postScriptName, size: scaledSize)
            ?? NSFont.systemFont(ofSize: scaledSize)

        // Update the text storage with the new attributed string.
        // Use NSAttributedString bridging for NSTextStorage compatibility.
        if let textStorage = textView.textStorage {
            textStorage.beginEditing()
            textStorage.setAttributedString(renderedString)
            textStorage.endEditing()
        }

        // Restore scroll position after the layout pass completes.
        // A short defer (50ms) gives NSLayoutManager time to finish relayout so the
        // document height is accurate before we scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak textView] in
            guard let scrollView = textView?.enclosingScrollView else { return }
            let maxY = max(
                0,
                (scrollView.documentView?.frame.height ?? 0)
                    - scrollView.contentView.bounds.height
            )
            let clampedY = max(0, min(targetOffset, maxY))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
