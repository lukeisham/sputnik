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

    /// Re-highlights the full document for `mode`. No-op for `.plainText`.
    public func highlight(mode: EditorMode) {
        guard mode != .plainText else { return }

        Task(priority: .utility) { [weak self] in
            guard let self, let storage = self.textStorage else { return }
            // Capture text on main actor before leaving it.
            let text = await MainActor.run { storage.string }
            let attrs = self.buildAttributes(for: mode, text: text)

            await MainActor.run { [weak self] in
                guard let self, let storage = self.textStorage else { return }
                let full = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.removeAttribute(.foregroundColor, range: full)
                for (range, color) in attrs {
                    guard range.location + range.length <= storage.length else { continue }
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
                storage.endEditing()
            }
        }
    }

    // MARK: - Pattern matching (runs off main actor)

    private func buildAttributes(
        for mode: EditorMode,
        text: String
    ) -> [(NSRange, NSColor)] {
        switch mode {
        case .plainText: return []
        case .markdown:  return markdownAttributes(in: text)
        case .html:      return htmlAttributes(in: text)
        case .asciiArt:  return []   // ASCII art has no colour highlighting.
        }
    }

    private func markdownAttributes(in text: String) -> [(NSRange, NSColor)] {
        var result: [(NSRange, NSColor)] = []
        let ns = text as NSString

        let patterns: [(String, NSColor)] = [
            (#"^#{1,6} .+"#,              .systemBlue),    // Headings
            (#"\*\*[^*]+\*\*"#,           .systemPurple),  // Bold
            (#"\*[^*]+\*"#,               .systemPink),    // Italic
            (#"`[^`]+`"#,                 .systemGreen),   // Inline code
            (#"```[\s\S]*?```"#,          .systemGreen),   // Fenced code
            (#"\[[^\]]+\]\([^)]+\)"#,     .systemOrange),  // Links
        ]

        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: .anchorsMatchLines
            ) else { continue }
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
            (#"<!DOCTYPE[^>]*>"#,         .systemPurple, [.caseInsensitive]),
            (#"<!--[\s\S]*?-->"#,         .systemGray,   [.dotMatchesLineSeparators]),
            (#"</?[a-zA-Z][^>]*>"#,       .systemBlue,   []),
            (#"[a-zA-Z-]+=\"[^\"]*\""#,   .systemOrange, []),
        ]

        for (pattern, color, opts) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            let range = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: text, range: range) {
                result.append((match.range, color))
            }
        }
        return result
    }
}
