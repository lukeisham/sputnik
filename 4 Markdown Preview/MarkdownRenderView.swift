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

    // MARK: - Init

    /// Creates the render view.
    ///
    /// - Parameters:
    ///   - renderedString: The parsed Markdown to display.
    ///   - fontScale:      Font zoom factor (1.0 = default).
    ///   - coordinator:    The link-click coordinator.
    ///   - settings:       The app settings store (for per-panel font/background).
    ///   - scrollOffset:   Binding for per-document scroll offset.
    ///   - printAction:    Binding set by the view with the print closure.
    public init(
        renderedString: NSAttributedString,
        fontScale: CGFloat,
        coordinator: MarkdownPreviewCoordinator,
        settings: SettingsStore,
        scrollOffset: Binding<CGFloat> = .constant(0),
        printAction: Binding<(() -> Void)?> = .constant(nil)
    ) {
        self.renderedString = renderedString
        self.fontScale = fontScale
        self.coordinator = coordinator
        self.settings = settings
        self.scrollOffset = scrollOffset
        _printAction = printAction
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

        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        // Reapply background from settings (F-4) — may have changed since last update.
        textView.backgroundColor = NSColor(settings.markdownPreviewBackground)

        // Keep the coordinator's binding pointing at the current document's slot so
        // the scroll observer always writes to the right entry in the panel's dict.
        context.coordinator.scrollOffsetBinding = scrollOffset

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
                guard let y = textView?.enclosingScrollView?.documentVisibleRect.origin.y else {
                    return
                }
                weakCoordinator?.scrollOffsetBinding?.wrappedValue = y
            }
        }

        // Wire the print action so the panel's overflow menu can trigger printing.
        printAction = { [weak textView] in
            guard let textView, let window = textView.window else { return }
            let printOp = NSPrintOperation(view: textView, printInfo: .shared)
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
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
