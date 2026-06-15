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

    // MARK: - Settings

    /// When `false`, fenced code blocks render as plain monospace with no token colours.
    /// Toggled from Settings ▸ Editor ▸ "Code block highlighting".
    public var codeBlockHighlightEnabled: Bool = true

    // MARK: - Cache

    /// Cached HTML attributes keyed by the opening fence's character location.
    /// Cleared on mode change; entries invalidated when `editedRange` overlaps the block.
    private var codeBlockCache: [Int: [(NSRange, NSColor)]] = [:]

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
            guard let self else { return }
            // Hop to main actor; return String (Sendable) so NSTextStorage isn't captured.
            guard let text = await MainActor.run(body: { [weak self] in self?.textStorage?.string })
            else { return }
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
        case .markdown:  return markdownAttributes(in: text)
        case .html:      return htmlAttributes(in: text)
        case .json:      return jsonAttributes(in: text)
        case .asciiArt:  return []  // ASCII art has no colour highlighting.
        }
    }

    // MARK: - Markdown highlighting

    private func markdownAttributes(in text: String) -> [(NSRange, NSColor)] {
        var result: [(NSRange, NSColor)] = []
        let ns = text as NSString

        // Step 1: Find all fenced code blocks and collect their ranges for exclusion.
        let codeBlocks = fencedCodeBlocks(in: text)
        let codeBlockRanges = codeBlocks.map { $0.range }

        // Step 2: Apply HTML highlighting inside ```html blocks.
        if codeBlockHighlightEnabled {
            for (blockRange, language) in codeBlocks where language == "html" {
                let codeBody = ns.substring(with: blockRange)

                // Check cache first.
                let htmlAttrs: [(NSRange, NSColor)]
                if let cached = codeBlockCache[blockRange.location] {
                    htmlAttrs = cached
                } else {
                    htmlAttrs = htmlAttributes(in: codeBody)
                    codeBlockCache[blockRange.location] = htmlAttrs
                }

                // Offset HTML attribute ranges from code-body-relative to document-relative.
                for (range, color) in htmlAttrs {
                    let docRange = NSRange(
                        location: blockRange.location + range.location,
                        length: range.length)
                    result.append((docRange, color))
                }
            }
        }

        // Step 3: Apply outer-Markdown patterns only to ranges outside code blocks.
        let outerPatterns: [(String, NSColor)] = [
            ("^#{1,6} .+", .systemBlue),  // Headings
            ("\\*\\*[^*]+\\*\\*", .systemPurple),  // Bold
            ("\\*[^*]+\\*", .systemPink),  // Italic
            ("`[^`]+`", .systemGreen),  // Inline code
            ("\\[[^\\]]+\\]\\([^)]+\\)", .systemOrange),  // Links
        ]

        for (pattern, color) in outerPatterns {
            guard
                let regex = try? NSRegularExpression(
                    pattern: pattern,
                    options: .anchorsMatchLines
                )
            else { continue }
            let fullRange = NSRange(location: 0, length: ns.length)
            for match in regex.matches(in: text, range: fullRange) {
                // Skip matches that fall inside a code block.
                let overlapsCode = codeBlockRanges.contains { cbRange in
                    NSIntersectionRange(match.range, cbRange).length > 0
                }
                guard !overlapsCode else { continue }
                result.append((match.range, color))
            }
        }
        return result
    }

    // MARK: - Fenced code block parser

    /// Scans Markdown text for fenced code blocks (``` or ~~~ delimiters).
    /// Returns each block's content range (between the fences) and its optional language tag.
    ///
    /// Language tag is the word immediately following the opening fence, lowercased and trimmed.
    /// `nil` when no tag is present. Tilde fences (`~~~`) are treated identically to backtick
    /// fences. Unclosed fences (no matching closing delimiter) are silently skipped.
    private func fencedCodeBlocks(in text: String) -> [(range: NSRange, language: String?)] {
        var blocks: [(NSRange, String?)] = []
        let lines = text.components(separatedBy: "\n")
        var lineOffset = 0  // running UTF-16 start of the current line

        // Regex to match an opening fence: ^(```|~~~)(\S*)\s*$
        guard
            let openRegex = try? NSRegularExpression(
                pattern: "^(```|~~~)(\\S*)\\s*$", options: []
            )
        else { return blocks }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let lineNS = line as NSString

            guard
                let match = openRegex.firstMatch(
                    in: line, range: NSRange(location: 0, length: lineNS.length))
            else {
                lineOffset += lineNS.length + 1  // +1 for newline
                i += 1
                continue
            }

            let fenceChar = lineNS.substring(with: match.range(at: 1))  // ``` or ~~~
            let langRaw = lineNS.substring(with: match.range(at: 2))
            let language: String? =
                langRaw.isEmpty ? nil : langRaw.lowercased().trimmingCharacters(in: .whitespaces)

            // Content starts on the next line (after the opening fence + newline).
            let contentStart = lineOffset + lineNS.length + 1
            i += 1
            lineOffset += lineNS.length + 1

            // Search for the matching closing fence.
            let closingPattern: String
            if fenceChar.hasPrefix("`") {
                closingPattern = "^```\\s*$"
            } else {
                closingPattern = "^~~~\\s*$"
            }

            guard let closeRegex = try? NSRegularExpression(pattern: closingPattern, options: [])
            else { continue }

            var foundClose = false
            while i < lines.count {
                let closeLine = lines[i]
                let closeNS = closeLine as NSString
                if closeRegex.firstMatch(
                    in: closeLine, range: NSRange(location: 0, length: closeNS.length)) != nil
                {
                    let contentEnd = lineOffset  // start of closing line
                    let contentLength = contentEnd - contentStart
                    if contentLength > 0 {
                        let contentRange = NSRange(location: contentStart, length: contentLength)
                        blocks.append((contentRange, language))
                    } else {
                        let contentRange = NSRange(location: contentStart, length: 0)
                        blocks.append((contentRange, language))
                    }
                    lineOffset += closeNS.length + 1
                    i += 1
                    foundClose = true
                    break
                }
                lineOffset += closeNS.length + 1
                i += 1
            }

            if !foundClose {
                break
            }
        }

        return blocks
    }

    // MARK: - JSON highlighting

    /// Returns colour attributes for JSON tokens in `text`.
    ///
    /// Token classes and colours:
    /// - Keys (strings before `:`): `.systemBlue`
    /// - String values (strings not before `:`): `.systemGreen`
    /// - Numbers: `.systemOrange`
    /// - Keywords (`true`, `false`, `null`): `.systemPurple`
    func jsonAttributes(in text: String) -> [(NSRange, NSColor)] {
        var result: [(NSRange, NSColor)] = []
        let ns = text as NSString

        // 1. All quoted strings — then classify as key or value by context.
        let stringPattern = "\"(?:[^\"\\\\]|\\\\.)*\""
        guard let stringRegex = try? NSRegularExpression(pattern: stringPattern, options: []) else {
            return result
        }
        let fullRange = NSRange(location: 0, length: ns.length)
        for match in stringRegex.matches(in: text, range: fullRange) {
            // Determine if a colon follows this string (key context).
            let afterEnd = match.range.upperBound
            var nextNonSpace = afterEnd
            while nextNonSpace < ns.length {
                let ch = ns.character(at: nextNonSpace)
                if ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D {
                    nextNonSpace += 1
                } else {
                    break
                }
            }
            let isKey = nextNonSpace < ns.length && ns.character(at: nextNonSpace) == 0x3A // ":"
            result.append((match.range, isKey ? .systemBlue : .systemGreen))
        }

        // 2. Numbers (integer or floating-point, including negative).
        let numberPattern = "-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"
        if let numRegex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            for match in numRegex.matches(in: text, range: fullRange) {
                result.append((match.range, .systemOrange))
            }
        }

        // 3. Keywords: true, false, null.
        let keywordPattern = "\\b(?:true|false|null)\\b"
        if let kwRegex = try? NSRegularExpression(pattern: keywordPattern, options: []) {
            for match in kwRegex.matches(in: text, range: fullRange) {
                result.append((match.range, .systemPurple))
            }
        }

        return result
    }

    // MARK: - HTML highlighting

    private func htmlAttributes(in text: String) -> [(NSRange, NSColor)] {
        var result: [(NSRange, NSColor)] = []
        let ns = text as NSString

        let patterns: [(String, NSColor, NSRegularExpression.Options)] = [
            ("<!DOCTYPE[^>]*>", .systemPurple, [.caseInsensitive]),
            ("<!--[\\s\\S]*?-->", .systemGray, [.dotMatchesLineSeparators]),
            ("</?[a-zA-Z][^>]*>", .systemBlue, []),
            ("[a-zA-Z-]+=\"[^\"]*\"", .systemOrange, []),
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
