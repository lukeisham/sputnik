import AppKit
import FoundationModule

/// Stateless helper that bridges editor operations to the terminal panel.
///
/// All methods take their dependencies explicitly (`InterPanelRouter`, `NSTextView`) rather
/// than reaching into `EditorViewModel` state, making them testable in isolation. Extracted
/// from `EditorViewModel` to honour SR-6 (one responsibility per file). See ISS-139.
@MainActor
public enum EditorTerminalBridge {

    /// Sends the editor's current text selection to the active terminal session.
    /// With nothing selected, sends the current line instead.
    /// - Parameters:
    ///   - router: The inter-panel router for dispatching to the terminal.
    ///   - textView: The active editor text view.
    public static func sendSelection(to router: any InterPanelRouter, from textView: NSTextView) {
        let text = editorSelectionOrCurrentLine(textView: textView)
        guard !text.isEmpty else { return }
        router.sendToTerminal(text)
        router.focusTerminal()
    }

    /// Builds a shell command referencing the given file path and runs it in the terminal.
    /// - Parameters:
    ///   - url: The file URL to reference in the command.
    ///   - mode: The active editor mode, which determines the command.
    ///   - router: The inter-panel router for dispatching to the terminal.
    public static func runFile(url: URL, mode: EditorMode, router: any InterPanelRouter) {
        let escaped = url.path.shellEscaped
        let command: String
        switch mode {
        case .markdown:
            command = "cat \(escaped)"
        case .html:
            command = "open \(escaped)"
        case .json:
            command = "cat \(escaped) | python3 -m json.tool"
        case .asciiArt:
            command = "cat \(escaped)"
        case .plainText:
            command = "cat \(escaped)"
        }
        router.runInTerminal(command)
        router.focusTerminal()
    }

    /// Inserts the terminal's current selected text at the editor cursor.
    /// - Parameters:
    ///   - router: The inter-panel router for reading terminal selection.
    ///   - textView: The active editor text view to insert into.
    public static func insertTerminalSelection(router: any InterPanelRouter, textView: NSTextView) {
        guard let text = router.terminalCurrentSelection() else { return }
        insertText(text, at: textView)
    }

    /// Inserts the output of the last completed terminal command at the editor cursor.
    /// Falls back to terminal selection when no OSC 133 command output is available.
    /// - Parameters:
    ///   - router: The inter-panel router for reading command output.
    ///   - textView: The active editor text view to insert into.
    public static func insertLastCommandOutput(router: any InterPanelRouter, textView: NSTextView) {
        let text =
            router.terminalLastCommandOutput()
            ?? router.terminalCurrentSelection()
        guard let text else { return }
        insertText(text, at: textView)
    }

    // MARK: - Private helpers

    /// Returns the selected text in the text view, or the current line if nothing
    /// is selected. Returns an empty string for an empty editor.
    private static func editorSelectionOrCurrentLine(textView: NSTextView) -> String {
        let range = textView.selectedRange()
        let nsString = textView.string as NSString
        if range.length > 0 {
            return nsString.substring(with: range)
        }
        // Fall back to current line.
        let currentLineRange = nsString.lineRange(for: range)
        let line = nsString.substring(with: currentLineRange)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inserts the given text at the editor cursor, replacing any selected range.
    private static func insertText(_ text: String, at textView: NSTextView) {
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: text) {
            textView.replaceCharacters(in: range, with: text)
            textView.didChangeText()
        }
    }
}
