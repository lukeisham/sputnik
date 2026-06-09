import AppKit
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

    /// The rendered Markdown content to display.
    let renderedString: AttributedString

    /// The current font-scale factor for the content.
    let fontScale: CGFloat

    /// The coordinator that handles link clicks.
    let coordinator: MarkdownPreviewCoordinator

    /// The settings store, read for per-panel font and background (F-4).
    let settings: SettingsStore

    // MARK: - Init

    /// Creates the render view.
    ///
    /// - Parameters:
    ///   - renderedString: The parsed Markdown to display.
    ///   - fontScale:      Font zoom factor (1.0 = default).
    ///   - coordinator:    The link-click coordinator.
    ///   - settings:       The app settings store (for per-panel font/background).
    public init(
        renderedString: AttributedString,
        fontScale: CGFloat,
        coordinator: MarkdownPreviewCoordinator,
        settings: SettingsStore
    ) {
        self.renderedString = renderedString
        self.fontScale = fontScale
        self.coordinator = coordinator
        self.settings = settings
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

        // Width tracks the container so text wraps naturally.
        textView.textContainer?.widthTracksContainer = true
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

        // Only update the text storage when the content has actually changed,
        // to avoid unnecessary layout invalidation.
        guard textView.textStorage?.string != String(renderedString.characters) else {
            return
        }

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
            textStorage.setAttributedString(NSAttributedString(renderedString))
            textStorage.endEditing()
        }
    }
}
