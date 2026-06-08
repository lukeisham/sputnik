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

    public init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
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

        context.coordinator.textView     = textView
        context.coordinator.ghostOverlay = overlay
        context.coordinator.search       = search

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

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        public func textDidChange(_ notification: Notification) {
            viewModel.isDirty = true
            // Invalidate ruler on every edit so line numbers stay current.
            if let tv = notification.object as? NSTextView {
                tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            }
        }
    }
}
