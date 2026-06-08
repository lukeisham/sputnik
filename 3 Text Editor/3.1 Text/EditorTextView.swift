import AppKit

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
           event.charactersIgnoringModifiers == "f" {
            searchController?.toggleVisible()
            return
        }

        // All other keys: clear ghost text, then proceed with normal AppKit handling.
        ghostTextOverlay?.clear()
        super.keyDown(with: event)
    }
}
