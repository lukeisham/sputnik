import AppKit
import Foundation

/// Coordinates between the ASCII Studio panel and the active document editor.
///
/// Handles inserting ASCII art at the cursor position in the text view and
/// routing the **⌘⌥A / Format → ASCII Studio** command to open/raise the
/// dockable panel instead of the old floating `NSPanel`.
///
/// All operations are on `@MainActor`.
@MainActor
public enum ASCIIStudioCoordinator {

    /// Inserts `text` at the current cursor position in `textView`.
    /// No-op if the text view has no text storage.
    /// - Parameters:
    ///   - text: The ASCII art string to insert.
    ///   - textView: The target text view.
    public static func insertAtCursor(_ text: String, into textView: NSTextView) {
        guard !text.isEmpty, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        storage.replaceCharacters(in: range, with: text)
    }

    /// Returns the currently-focused text view from the active window.
    /// Scans the app's key window for a first responder of type `NSTextView`.
    public static func activeTextView() -> NSTextView? {
        guard let window = NSApp.keyWindow else { return nil }
        return window.firstResponder as? NSTextView
    }
}
