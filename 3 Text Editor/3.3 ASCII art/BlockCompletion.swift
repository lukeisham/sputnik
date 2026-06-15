import AppKit

/// Expands a partial box-drawing pattern to a complete ASCII frame on Tab acceptance.
///
/// Pairs with `ASCIIArtLanguageProvider` (tier 1): the provider stages a `Payload`
/// here, `GhostTextOverlay` shows the preview string, and on Tab `EditorTextView`
/// calls `GhostTextOverlay.accept()` which accepts the preview characters. For a full
/// multi-line frame insertion, call `apply(to:)` from the Tab handler instead.
@MainActor
public final class BlockCompletion {

    // MARK: - Payload

    public struct Payload: Sendable {
        /// The partial pattern at the cursor that triggered this completion.
        public let pattern: String
        /// The full ASCII frame to insert (may be multi-line).
        public let frame: String
        /// A short single-line preview shown as ghost text.
        public let preview: String
    }

    // MARK: - State

    private var staged: Payload?

    // MARK: - Public interface

    /// Stores a pending block-completion payload.
    public func stage(_ payload: Payload) {
        staged = payload
    }

    /// Applies the staged payload to `textView`, replacing the trigger pattern.
    ///
    /// No-op when no payload is staged, or when the trigger pattern is no longer
    /// found at the expected cursor position (e.g. user moved the cursor).
    public func apply(to textView: NSTextView) {
        guard let payload = staged,
              let storage = textView.textStorage else { return }
        staged = nil

        let cursorPos   = textView.selectedRange().location
        let text        = storage.string as NSString
        let lookback    = min(payload.pattern.count, cursorPos)
        let searchRange = NSRange(location: cursorPos - lookback, length: lookback)
        let found       = text.range(of: payload.pattern, range: searchRange)
        guard found.location != NSNotFound else { return }

        // Register undo before expanding so ⌘Z restores the trigger pattern.
        let expandedRange = NSRange(location: found.location, length: (payload.frame as NSString).length)
        textView.undoManager?.registerUndo(withTarget: textView) { tv in
            tv.textStorage?.replaceCharacters(in: expandedRange, with: payload.pattern)
        }
        storage.replaceCharacters(in: found, with: payload.frame)
    }

    /// Clears any staged payload without applying it.
    public func discard() {
        staged = nil
    }
}
