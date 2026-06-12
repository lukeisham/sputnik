import Foundation

/// Protocol for editor→terminal integration: send text/commands and read
/// terminal selection or last-command output.
///
/// Owned by Foundation alongside `TerminalLifecycle` (2.6). Module 7 implements
/// this protocol so the editor (module 3) can drive the terminal without importing
/// module 7 directly (SR-1 — Foundation stays an interface layer).
///
/// `WindowState` stores a reference to an optional `TerminalCommanding` instance
/// set by `TerminalView.onAppear`; the `InterPanelRouter` and editor commands
/// resolve it from the active window.
@MainActor
public protocol TerminalCommanding: AnyObject {
    /// Sends raw text to the terminal's stdin (no trailing newline).
    /// Used for "Send Selection" — the text is inserted as keystrokes.
    func sendText(_ text: String)

    /// Sends a command to the terminal's stdin, appending a trailing newline
    /// so the shell executes it immediately.
    func sendCommand(_ command: String)

    /// Returns the currently selected text in the terminal, or `nil` if
    /// no selection exists. Falls back to last-N scrollback lines when
    /// there is no active selection (graceful degradation).
    func currentSelectionText() -> String?

    /// Returns the captured output text of the last completed command,
    /// as delimited by OSC 133 shell-integration markers.
    ///
    /// Returns `nil` when no command has completed yet, or when
    /// shell-integration markers are not present (e.g. before the first
    /// prompt, or when running a non-Zsh shell).
    func lastCommandOutput() -> String?
}
