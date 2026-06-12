import Foundation

/// Protocol for menu commands that the editor implements (Save, Save As, Render as HTML, ASCII Studio).
///
/// SR-1: Foundation calls methods on this protocol (registered in AppState) without
/// importing module 3. The editor registers itself at launch, keeping Foundation
/// an interface layer that does not know about TextEditorModule.
@MainActor
public protocol EditorCommandHandling: AnyObject {
    /// Saves the current buffer to the open file.
    func save() async throws

    /// Opens a Save As dialog and writes to the selected file.
    func saveAs(to newURL: URL) async throws

    /// Opens the HTML Preview panel with the current file.
    func renderAsHTML() async throws

    /// Presents the ASCII Studio for the active editor.
    func showASCIIStudio() async throws

    /// Sends the editor's current text selection (or current line if none)
    /// to the active terminal session.
    func sendSelectionToTerminal()

    /// Builds a shell command referencing the active document's file path
    /// (shell-escaped) and runs it in the active terminal session.
    /// No-op when there is no active file.
    func runCurrentFileInTerminal()

    /// Inserts the terminal's current selected text at the editor cursor.
    /// No-op when the terminal has no selection.
    func insertTerminalSelection()

    /// Inserts the output of the last completed terminal command
    /// (delimited by OSC 133 markers) at the editor cursor.
    /// Falls back to terminal selection when no marked command output is available.
    func insertLastCommandOutput()

    /// Scrolls the editor to make the given source line (0-based) visible and places
    /// the caret at that line. No-op when the text view is unavailable or `line` is
    /// out of range. Used by preview panels for ⌘-click-to-source navigation (ISS-065).
    func revealLine(_ line: Int)

    /// Flushes the editor's current caret position and scroll offset into the
    /// given `WindowState`'s `documentViewStates` dictionary, keyed by the active
    /// document's `id`.
    ///
    /// Called during `AppDelegate.applicationWillTerminate` before descriptors
    /// are collected, so per-document view state is persisted across relaunch.
    /// Implementations read from `NSTextView.selectedRange` and
    /// `enclosingScrollView?.contentView.bounds.origin`.
    func flushViewState(to windowState: WindowState?)
}
