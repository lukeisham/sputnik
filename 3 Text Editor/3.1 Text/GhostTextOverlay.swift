import AppKit

/// Renders an inline completion suggestion as greyed text appended after the cursor
/// in `NSTextStorage`.
///
/// **Lifecycle:** `show(_:)` inserts ghost characters with a distinctive attribute;
/// `accept()` moves the cursor past them (keeping the text); `clear()` removes them.
/// `EditorTextView` calls `accept()` on Tab and `clear()` on any other keypress.
///
/// **Shared by sub-modules 3.2, 3.3, and 3.4. Lives in 3.1 because it mutates
/// `NSTextStorage` and is coupled to the `NSTextView` editing surface. Sub-modules
/// must not re-implement or copy this type (SC-2, SC-8).**
///
/// Note: ghost-text insertions are wrapped in `undoManager.disableUndoRegistration` so
/// they are invisible to the undo stack, and `isDirty` is not affected.
@MainActor
public final class GhostTextOverlay {

    // MARK: - Internal attribute key — used to identify ghost text for removal

    static let ghostAttributeKey = NSAttributedString.Key("com.sputnik.ghostText")

    // MARK: - State

    private weak var textView: NSTextView?
    private var suggestionLength: Int = 0

    /// `true` when a suggestion is currently visible in the text view.
    public private(set) var isVisible: Bool = false

    public init(textView: NSTextView) {
        self.textView = textView
    }

    // MARK: - Public interface

    /// Inserts `suggestion` as greyed ghost text immediately after the cursor.
    ///
    /// Replaces any existing suggestion atomically. The insertion bypasses the undo
    /// stack and does not mark the document dirty.
    public func show(_ suggestion: String) {
        guard !suggestion.isEmpty else { clear(); return }
        guard let textView = textView,
              let storage  = textView.textStorage else { return }

        clear()  // Remove any previous ghost text first.

        let cursorPos = textView.selectedRange().location
        guard cursorPos <= storage.length else { return }

        let ghostAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor:    NSColor.tertiaryLabelColor,
            .font:               textView.font
                                 ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            Self.ghostAttributeKey: true,
        ]
        let ghostStr = NSAttributedString(string: suggestion, attributes: ghostAttrs)

        textView.undoManager?.disableUndoRegistration()
        storage.beginEditing()
        storage.insert(ghostStr, at: cursorPos)
        storage.endEditing()
        textView.undoManager?.enableUndoRegistration()

        suggestionLength = suggestion.count
        isVisible        = true

        // Keep the insertion point before the ghost text.
        textView.setSelectedRange(NSRange(location: cursorPos, length: 0))
    }

    /// Moves the cursor past the ghost text, making the suggestion permanent.
    public func accept() {
        guard isVisible, let textView = textView else { return }

        // Strip the ghost attribute so the accepted text looks like normal text.
        if let storage = textView.textStorage {
            let cursorPos   = textView.selectedRange().location
            let ghostRange  = NSRange(location: cursorPos, length: suggestionLength)
            guard ghostRange.location + ghostRange.length <= storage.length else {
                isVisible = false; suggestionLength = 0; return
            }
            storage.beginEditing()
            storage.removeAttribute(Self.ghostAttributeKey, range: ghostRange)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: ghostRange)
            storage.endEditing()
        }

        let cursorPos = textView.selectedRange().location
        let newPos    = min(cursorPos + suggestionLength,
                           textView.textStorage?.length ?? 0)
        textView.setSelectedRange(NSRange(location: newPos, length: 0))

        suggestionLength = 0
        isVisible        = false
    }

    /// Removes the ghost text from `NSTextStorage` without accepting it.
    public func clear() {
        guard isVisible,
              let textView = textView,
              let storage  = textView.textStorage else {
            isVisible = false; suggestionLength = 0; return
        }

        let cursorPos   = textView.selectedRange().location
        let ghostRange  = NSRange(location: cursorPos, length: suggestionLength)
        guard ghostRange.location + ghostRange.length <= storage.length else {
            isVisible = false; suggestionLength = 0; return
        }

        textView.undoManager?.disableUndoRegistration()
        storage.beginEditing()
        storage.deleteCharacters(in: ghostRange)
        storage.endEditing()
        textView.undoManager?.enableUndoRegistration()

        suggestionLength = 0
        isVisible        = false
    }
}
