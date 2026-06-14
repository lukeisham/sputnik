import AppKit
import SwiftUI

/// An `NSViewRepresentable` wrapper around a plain `NSTextView` for unstructured
/// scratchpad text entry.
///
/// **SW-3 justification:** `NSTextView` provides raw plain-text editing performance
/// that SwiftUI's `TextEditor` cannot match for an unstructured, always-editable
/// scratchpad. This is the only `NSViewRepresentable` in the Foundation layer and
/// is documented per SW-3.
public struct ScratchpadTextView: NSViewRepresentable {

    @Binding var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.isRichText = false
        textView.usesFindPanel = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Refresh the coordinator's reference to the current struct value (ISS-098).
        // The coordinator captured a copy at `makeCoordinator` time; without this the
        // standard SwiftUI representable pattern would read stale non-binding state.
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadTextView

        public init(_ parent: ScratchpadTextView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
