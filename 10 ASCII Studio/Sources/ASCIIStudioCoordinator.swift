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

    // MARK: - Focus tracking (ISS-118)

    /// The most recent `EditorTextView` that became first responder.
    /// Updated via `Notification.Name.editorTextViewDidBecomeFirstResponder` when
    /// `startTracking()` has been called. Weak so the coordinator never retains the view.
    public private(set) static weak var lastKnownTextView: NSTextView? = nil

    private static var _trackingObserver: NSObjectProtocol? = nil

    /// Begins observing editor-focus notifications. Safe to call multiple times.
    /// Call from the Studio panel's `.task` modifier.
    public static func startTracking() {
        guard _trackingObserver == nil else { return }
        _trackingObserver = NotificationCenter.default.addObserver(
            forName: .editorTextViewDidBecomeFirstResponder,
            object: nil,
            queue: .main
        ) { note in
            // queue: .main guarantees we're on the main thread; assert main-actor isolation.
            MainActor.assumeIsolated {
                lastKnownTextView = note.object as? NSTextView
            }
        }
    }

    // MARK: - Core operations

    /// Inserts `text` at the current cursor position in `textView`.
    /// No-op if the text view has no text storage.
    public static func insertAtCursor(_ text: String, into textView: NSTextView) {
        guard !text.isEmpty, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        storage.replaceCharacters(in: range, with: text)
    }

    /// Returns the currently-focused text view, falling back to the last known editor.
    /// The fallback is needed when the Studio panel is focused and the key window's
    /// `firstResponder` is a SwiftUI control rather than the editor.
    public static func activeTextView() -> NSTextView? {
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView { return tv }
        return lastKnownTextView
    }
}

// MARK: - Notification name

public extension Notification.Name {
    /// Posted by `EditorTextView` when it successfully becomes first responder.
    static let editorTextViewDidBecomeFirstResponder = Notification.Name(
        "EditorTextViewDidBecomeFirstResponder"
    )
}
