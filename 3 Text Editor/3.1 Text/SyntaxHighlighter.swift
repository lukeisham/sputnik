import AppKit

/// Applies syntax-colour attributes to `NSTextStorage` for the active `EditorMode`.
///
/// Runs on `Task(priority: .utility)` to keep the typing path clear (SR-4, SW-1).
/// Attribute writes hop back to `@MainActor` as required by AppKit.
///
/// **Shared by sub-modules 3.2–3.4; lives in 3.1 because it is tightly coupled to
/// `NSTextStorage` and `EditorMode`. Sub-modules must not re-implement or copy this
/// type (SC-2 — "defined once in 3.1").**
public final class SyntaxHighlighter {

    private weak var textStorage: NSTextStorage?

    public init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
    }

    // MARK: - Public interface

    /// Re-highlights the document for `mode`, optionally scoped to an edited range.
    /// No-op for `.plainText`.
    ///
    /// - Parameter editedRange: The character range that changed. `nil` = full document
    ///   (used on initial load). Only the affected range (plus a look-behind margin) is
    ///   re-coloured — O(range) instead of O(n) per keystroke (ISS-057).
    public func highlight(mode: EditorMode, editedRange: NSRange? = nil) {
        guard mode != .plainText else { return }

        Task(priority: .utility) { [weak self] in
            guard let self, let storage = self.textStorage else { return }
            // Capture text on main actor before leaving it.
            let text = await MainActor.run { storage.string }
            let highlightRange = self.expandedRange(for: editedRange, in: text)
            let segment = (text as NSString).substring(with: highlightRange)
            let attrs = self.buildAttributes(
                for: mode, text: segment,
                baseOffset: highlightRange.location)

            await MainActor.run { [weak self] in
                guard let self, let storage = self.textStorage else { return }
                storage.beginEditing()
                storage.removeAttribute(.foregroundColor, range: highlightRange)
                for (range, color) in attrs {
                    guard range.location + range.length <= storage.length else { continue }
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
                storage.endEditing()
            }
        }
    }

    // MARK: - Pattern matching (runs off main actor)

    /// Expands a character range to include full surrounding lines.
    /// If `range` is nil, returns the full document range.
    /// The look-behind margin (5 lines) catches multi-line constructs such as fenced
    /// code blocks whose opening delimiter may be well above the actual edit (ISS-057).
    private func expandedRange(for range: NSRange?, in text: String) -> NSRange {
        guard let range = range else {
            return NSRange(location: 0, length: (text as NSString).length)
        }
        let nsText = text as NSString
        let lookBackLines = 5
        var startLine = nsText.lineRange(for: range).location
        // Walk back N lines to catch multi-line construct delimiters.
        for _ in 0..<lookBackLines {
            guard startLine > 0 else { break }
            startLine = nsText.lineRange(for: NSRange(location: startLine - 1, length: 0)).location
        }
        let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        let endLocation = min(nsText.length, lineRange.upperBound)
        return NSRange(location: startLine, length: endLocation - startLine)
    }

    private func buildAttributes(
        for mode: EditorMode,
        text: String,
        baseOffset: Int = 0
    ) -> [(NSRange, NSColor)] {
        switch mode {
        case .plainText: return []
        case .markdown: return markdownAttributes(in: text)
        case .html: return htmlAttributes(in: text)
        case .asciiArt: return []  // ASCII art has no colour highlighting.
        }
    }

    private func markdownAttributes(in text: String) -> [(NSRange, NSColor)] {
        var result: [(NSRange, NSColor)] = []
        let ns = text as NSString

        let patterns: [(String, NSColor)] = [
            (#"^#{1,6} .+"#, .systemBlue),  // Headings
            (#"\*\*[^*]+\*\*"#, .systemPurple),  // Bold
            (#"\*[^*]+\*"#, .systemPink),  // Italic
            (#"`[^`]+`"#, .systemGreen),  // Inline code
            (#"```[\s\S]*?```"#, .systemGreen),  // Fenced code
            (#"\[[^\]]+\]\([^)]+\)"#, .systemOrange),  // Links
        ]

        for (pattern, color) in patterns {
            guard
                let regex = try? NSRegularExpression(
                    pattern: pattern,
                    options: .anchorsMatchLines
                )
            else { continue }
            let range = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: text, range: range) {
                result.append((match.range, color))
            }
        }
        return result
    }

    private func htmlAttributes(in text: String) -> [(NSRange, NSColor)] {
        var result: [(NSRange, NSColor)] = []
        let ns = text as NSString

        let patterns: [(String, NSColor, NSRegularExpression.Options)] = [
            (#"<!DOCTYPE[^>]*>"#, .systemPurple, [.caseInsensitive]),
            (#"<!--[\s\S]*?-->"#, .systemGray, [.dotMatchesLineSeparators]),
            (#"</?[a-zA-Z][^>]*>"#, .systemBlue, []),
            (#"[a-zA-Z-]+=\"[^\"]*\""#, .systemOrange, []),
        ]

        for (pattern, color, opts) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else {
                continue
            }
            let range = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: text, range: range) {
                result.append((match.range, color))
            }
        }
        return result
    }
}
