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
/// comfortable text-container inset. The bridge **owns its `NSScrollView`** (ISS-096)
/// rather than reaching into SwiftUI's private `enclosingScrollView`, which is not
/// API-contracted and has broken between macOS releases.
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

    /// The fractional scroll position to apply for editor→preview sync (ISS-063, Step 5).
    /// `nil` when sync is disabled or the document exceeds the large-file threshold (Step 10).
    /// Range 0.0 (top) … 1.0 (bottom). Applied in `updateNSView` only when the fraction
    /// changes by more than 0.005 from the last applied value, to suppress feedback loops.
    let syncScrollFraction: Double?

    /// `true` when the active document is in large-file degraded mode (>80k chars).
    /// Scroll restore uses `asyncAfter` instead of `ensureLayout` to avoid blocking
    /// the main thread on large documents (ISS-090).
    let isLargeFile: Bool

    // MARK: - Init

    /// The view model, used to publish the scroll view for the minimap.
    let viewModel: MarkdownPreviewViewModel

    /// Creates the render view.
    ///
    /// - Parameters:
    ///   - renderedString: The parsed Markdown to display.
    ///   - fontScale:      Font zoom factor (1.0 = default).
    ///   - coordinator:    The link-click coordinator.
    ///   - settings:       The app settings store (for per-panel font/background).
    ///   - scrollOffset:   Binding for per-document scroll offset.
    ///   - viewModel:      The Markdown preview view model.
    ///
    /// Print / Save-as-PDF / Save-as-Markdown actions are exposed on the
    /// `MarkdownPreviewCoordinator` (wired once in `makeNSView`), not via bindings —
    /// see ISS-095. The parent panel reads them directly off the coordinator.
    public init(
        renderedString: NSAttributedString,
        fontScale: CGFloat,
        coordinator: MarkdownPreviewCoordinator,
        settings: SettingsStore,
        scrollOffset: Binding<CGFloat> = .constant(0),
        syncScrollFraction: Double? = nil,
        isLargeFile: Bool = false,
        viewModel: MarkdownPreviewViewModel
    ) {
        self.renderedString = renderedString
        self.fontScale = fontScale
        self.coordinator = coordinator
        self.settings = settings
        self.scrollOffset = scrollOffset
        self.syncScrollFraction = syncScrollFraction
        self.isLargeFile = isLargeFile
        self.viewModel = viewModel
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> MarkdownPreviewCoordinator {
        coordinator
    }

    public func makeNSView(context: Context) -> NSScrollView {
        // The bridge owns its scroll view (ISS-096). `scrollableTextView()` wires the
        // text view's resizing/containers correctly so we never touch the SwiftUI-private
        // `enclosingScrollView`.
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

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

        // Scroll configuration — the bridge owns this scroll view.
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

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

        // Register the scroll observer once against the owned clip view. The bridge owns
        // the scroll view, so the clip view is stable for the view's lifetime — no
        // per-update re-registration is needed (ISS-096). Removed in `dismantleNSView`.
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        context.coordinator.observedClipView = clipView
        let weakCoordinator = context.coordinator
        context.coordinator.scrollObserverToken = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak weakCoordinator, weak scrollView] _ in
            MainActor.assumeIsolated {
                guard let y = scrollView?.documentVisibleRect.origin.y else { return }
                weakCoordinator?.scrollOffsetBinding?.wrappedValue = y
            }
        }

        // Wire export/print actions once (ISS-095). Building these per-update inside
        // `updateNSView` ran on every AppState change and mutated SwiftUI bindings mid
        // view-update; exposing them on the coordinator keeps `updateNSView` a pure sync.
        // The closures capture `[weak textView]` and read the coordinator's export
        // context (`currentSourceText` / `currentDocumentName`) live at call time, so they
        // always reflect the active document.
        context.coordinator.printAction = { [weak textView] in
            guard let textView, let window = textView.window else { return }
            let printOp = NSPrintOperation(view: textView, printInfo: .shared)
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }

        context.coordinator.saveAsMarkdownAction = { [weak textView, weak weakCoordinator] in
            guard let textView, let window = textView.window else { return }
            let capturedSource = weakCoordinator?.currentSourceText ?? ""
            let capturedName = weakCoordinator?.currentDocumentName ?? ""
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

        // Publish the scroll view for the minimap binder.
        viewModel.scrollView = scrollView

        context.coordinator.saveAsPDFAction = { [weak textView] in
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

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

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
            let coordinator = context.coordinator
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak scrollView] in
                guard let scrollView else { return }
                coordinator.lastSyncScrollFraction = fraction
                let docH = scrollView.documentView?.frame.height ?? 0
                let viewH = scrollView.contentView.bounds.height
                guard docH > viewH else { return }
                let targetY = CGFloat(fraction) * (docH - viewH)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        // Only update the text storage when the content or font size has actually changed,
        // to avoid unnecessary layout invalidation.
        let desiredFontSize = settings.resolvedMarkdownPreviewFont.pointSize * fontScale
        let currentFontSize = textView.font?.pointSize ?? 0
        guard
            textView.textStorage?.string != renderedString.string
                || abs(currentFontSize - desiredFontSize) > 0.5
        else { return }

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

        // Restore scroll position after the layout pass completes (ISS-090).
        // For normal-size documents, ensureLayout forces a synchronous layout pass so
        // document height is accurate immediately, eliminating the fixed-timer race.
        // For large files, keep the asyncAfter fallback to avoid blocking the main thread.
        if !isLargeFile {
            if let container = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: container)
            }
            let maxY = max(
                0,
                (scrollView.documentView?.frame.height ?? 0)
                    - scrollView.contentView.bounds.height
            )
            let clampedY = max(0, min(targetOffset, maxY))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak scrollView] in
                guard let scrollView else { return }
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

    /// Removes the block-based scroll observer when the bridge is torn down (ISS-093).
    /// `NotificationCenter` block observers are never released automatically; without this
    /// the token (and the clip view it captures) leaks for the app's lifetime (SW-2).
    public static func dismantleNSView(
        _ nsView: NSScrollView, coordinator: MarkdownPreviewCoordinator
    ) {
        if let token = coordinator.scrollObserverToken {
            NotificationCenter.default.removeObserver(token)
            coordinator.scrollObserverToken = nil
        }
        coordinator.observedClipView = nil
    }
}
