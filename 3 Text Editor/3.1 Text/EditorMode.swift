import Foundation

/// The active language tier for the text editor.
///
/// Owned by `EditorViewModel`. Selected via the mode picker in the editor toolbar.
/// Controls which sub-module (3.2–3.4) is active and whether `SyntaxHighlighter`
/// applies language colours. `.plainText` disables all language assistance while
/// keeping the Markdown Preview panel available.
public enum EditorMode: String, Sendable, CaseIterable {
    case plainText = "Plain Text"
    case markdown  = "Markdown"
    case html      = "HTML"
    case asciiArt  = "ASCII Art"
}
