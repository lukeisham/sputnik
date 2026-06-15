import Foundation
import FoundationModule

/// Two-signal special element detector: syntax term (structural pattern) + contextual heading.
///
/// Detection is synchronous regex over the visible text range. A candidate is returned
/// only when a syntax term matches; the contextual heading is then captured (refining,
/// never suppressing, the result). After detection, the registry is consulted to
/// resolve a `definitionID`.
@MainActor
public final class SpecialElementDetector: SpecialElementDetecting {

    private let registry: SpecialElementRegistry

    public init(registry: SpecialElementRegistry = .shared) {
        self.registry = registry
    }

    // MARK: - SpecialElementDetecting

    public func detect(in text: String, selectedRange: NSRange, language: WritingAssistLanguage)
        -> SpecialElement?
    {
        guard selectedRange.location != NSNotFound, selectedRange.location < text.utf16.count else {
            return nil
        }

        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        let selectedLine = nsText.substring(with: lineRange)

        // Signal 1: detect syntax term.
        guard
            let (kind, syntaxTerm) = detectSyntaxTerm(
                in: selectedLine, fullText: text, selectedRange: selectedRange, language: language)
        else {
            return nil
        }

        // Signal 2: find nearest contextual heading.
        let contextHeading = findContextHeading(
            in: text, before: selectedRange.location, language: language)

        // Calculate insertion info.
        let insertInfo = insertionInfo(
            for: kind, text: text, selectedLineRange: lineRange, language: language)

        return SpecialElement(
            kind: kind,
            definitionID: nil,
            syntaxTerm: syntaxTerm,
            contextHeading: contextHeading,
            elementRange: lineRange,
            selectedLineRange: lineRange,
            insertionRange: insertInfo.range,
            insertionPrefix: insertInfo.prefix
        )
    }

    /// Called after detection to resolve the definitionID from the registry.
    func resolveDefinition(for element: SpecialElement) async -> SpecialElement? {
        let def = await registry.resolve(
            syntaxTerm: element.syntaxTerm, contextHeading: element.contextHeading)
        return SpecialElement(
            kind: element.kind,
            definitionID: def?.id,
            syntaxTerm: element.syntaxTerm,
            contextHeading: element.contextHeading,
            elementRange: element.elementRange,
            selectedLineRange: element.selectedLineRange,
            insertionRange: element.insertionRange,
            insertionPrefix: element.insertionPrefix
        )
    }

    // MARK: - Signal 1: Syntax Term Detection

    private func detectSyntaxTerm(
        in selectedLine: String,
        fullText: String,
        selectedRange: NSRange,
        language: WritingAssistLanguage
    ) -> (kind: SpecialElementKind, syntaxTerm: String)? {
        switch language {
        case .markdown, .spelling:
            return detectMarkdownSyntax(
                in: selectedLine, fullText: fullText, selectedRange: selectedRange)
        case .html:
            return detectHTMLSyntax(in: fullText, selectedRange: selectedRange)
        case .asciiArt:
            return detectASCIIArtSyntax(
                in: selectedLine, fullText: fullText, selectedRange: selectedRange)
        case .json:
            // JSON detection is not yet implemented.
            return nil
        case .grammar:
            // Grammar detection uses the parent document's mode (Markdown/HTML).
            // Default to Markdown detection for grammar.
            return detectMarkdownSyntax(
                in: selectedLine, fullText: fullText, selectedRange: selectedRange)
        }
    }

    // MARK: - Markdown Detection

    private func detectMarkdownSyntax(
        in selectedLine: String,
        fullText: String,
        selectedRange: NSRange
    ) -> (kind: SpecialElementKind, syntaxTerm: String)? {
        let nsText = fullText as NSString
        let trimmed = selectedLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // Blockquote: line starts with >
        if trimmed.hasPrefix(">") {
            return (.markdownBlockquote, "blockquote")
        }

        // Pipe table: at least 2 pipes on the line, and an adjacent line also has pipes.
        let pipeCount = trimmed.filter { $0 == "|" }.count
        if pipeCount >= 2 {
            // Check for an adjacent piped line.
            let lineIdx = nsText.lineRange(for: selectedRange).location
            if hasAdjacentPipeLine(text: fullText, around: lineIdx) {
                return (.markdownTableRow, "table")
            }
        }

        // Fenced code block: check if selection is inside ``` fences.
        if isInsideFencedCodeBlock(text: fullText, at: selectedRange.location) {
            return (.fencedCodeBlock, "code block")
        }

        return nil
    }

    private func hasAdjacentPipeLine(text: String, around lineStart: Int) -> Bool {
        let nsText = text as NSString
        // Check the line before.
        if lineStart > 0 {
            let prevLineRange = nsText.lineRange(
                for: NSRange(location: max(0, lineStart - 1), length: 0))
            if prevLineRange.location < lineStart {
                let prevLine = nsText.substring(with: prevLineRange).trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if prevLine.filter({ $0 == "|" }).count >= 2 { return true }
            }
        }
        // Check the line after.
        let afterStart = NSMaxRange(nsText.lineRange(for: NSRange(location: lineStart, length: 0)))
        if afterStart < text.utf16.count {
            let nextLineRange = nsText.lineRange(for: NSRange(location: afterStart, length: 0))
            if nextLineRange.location < text.utf16.count {
                let nextLine = nsText.substring(with: nextLineRange).trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if nextLine.filter({ $0 == "|" }).count >= 2 { return true }
            }
        }
        return false
    }

    private func isInsideFencedCodeBlock(text: String, at offset: Int) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        var lineStart = 0
        var fenceCount = 0
        for line in lines {
            let lineEnd = lineStart + line.utf16.count + 1  // +1 for newline
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenceCount += 1
            }
            if offset >= lineStart && offset < lineEnd {
                // Inside this line — we're in a code block if odd number of fences seen.
                return fenceCount % 2 == 1
            }
            lineStart = lineEnd
        }
        return false
    }

    // MARK: - HTML Detection

    private func detectHTMLSyntax(
        in fullText: String,
        selectedRange: NSRange
    ) -> (kind: SpecialElementKind, syntaxTerm: String)? {
        let offset = selectedRange.location
        let textBefore = (fullText as NSString).substring(to: min(offset, fullText.utf16.count))

        // Check for innermost enclosing tags by scanning backward from the offset.
        if let tag = findInnermostEnclosingTag(in: textBefore) {
            switch tag {
            case "tr":
                return (.htmlTableRow, "table")
            case "li":
                return (.htmlListItem, "list")
            case "pre", "code":
                return (.htmlCodeBlock, "code block")
            default:
                break
            }
        }
        return nil
    }

    /// Scans backward from the end of `textBefore` to find the innermost opening tag.
    private func findInnermostEnclosingTag(in textBefore: String) -> String? {
        // Simple tag scanner — finds the most recent opening tag before the offset.
        let tags = ["<tr>", "<li>", "<pre>", "<code>"]
        var lastTag: String?
        var lastIndex = -1

        for tag in tags {
            if let range = textBefore.range(of: tag, options: .backwards) {
                let idx = textBefore.distance(from: textBefore.startIndex, to: range.lowerBound)
                if idx > lastIndex {
                    lastIndex = idx
                    lastTag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                }
            }
        }

        return lastTag
    }

    // MARK: - ASCII Art Detection

    private func detectASCIIArtSyntax(
        in selectedLine: String,
        fullText: String,
        selectedRange: NSRange
    ) -> (kind: SpecialElementKind, syntaxTerm: String)? {
        let trimmed = selectedLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pipe table: has pipes and an adjacent line also has pipes.
        let pipeCount = trimmed.filter { $0 == "|" }.count
        if pipeCount >= 1 && hasAdjacentPipeLine(text: fullText, around: selectedRange.location) {
            return (.asciiTableRow, "table")
        }

        // Box region: contains box-drawing characters.
        let boxChars = CharacterSet(charactersIn: "─│╔╗╚╝║═╠╣╦╩╬╧╨╤╥╪╫╬╭╮╯╰╱╲╳◢◣◤◥")
        if trimmed.rangeOfCharacter(from: boxChars) != nil {
            return (.asciiBoxRegion, "box")
        }

        return nil
    }

    // MARK: - Signal 2: Contextual Heading

    /// Scans upward from the selection for the nearest heading.
    private func findContextHeading(
        in text: String, before offset: Int, language: WritingAssistLanguage
    )
        -> String?
    {
        guard offset > 0 else { return nil }

        let textBefore = (text as NSString).substring(to: min(offset, text.utf16.count))
        let lines = textBefore.components(separatedBy: .newlines)

        switch language {
        case .markdown, .grammar, .spelling:
            return findMarkdownHeading(lines: lines)
        case .html:
            return findHTMLHeading(lines: lines)
        case .asciiArt:
            return findASCIIHeading(lines: lines)
        case .json:
            return nil
        }
    }

    private func findMarkdownHeading(lines: [String]) -> String? {
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match ATX headings: # through ######
            if let headingRange = try? NSRegularExpression(pattern: "^#{1,6}\\s+(.*)$")
                .firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                let textRange = Range(headingRange.range(at: 1), in: trimmed)
            {
                return String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func findHTMLHeading(lines: [String]) -> String? {
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match <h1> through <h6> tags and capture inner text.
            let pattern = "<h[1-6][^>]*>(.*?)</h[1-6]>"
            if let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                .firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                let textRange = Range(match.range(at: 1), in: trimmed)
            {
                let inner = String(trimmed[textRange])
                // Strip any remaining HTML tags from the inner text.
                return inner.replacingOccurrences(
                    of: "<[^>]+>", with: "", options: .regularExpression
                )
                .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func findASCIIHeading(lines: [String]) -> String? {
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Heuristic: all-caps line or a line followed by an underline (=== or ---).
            // Check if this line is all-caps (3+ chars) and not obviously a border.
            if trimmed.utf16.count >= 3,
                trimmed.uppercased() == trimmed,
                trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "─│╔╗╚╝║═")) == nil
            {
                return trimmed
            }
        }
        return nil
    }

    // MARK: - Insertion Info

    private func insertionInfo(
        for kind: SpecialElementKind,
        text: String,
        selectedLineRange: NSRange,
        language: WritingAssistLanguage
    ) -> (range: NSRange, prefix: String) {
        let nsText = text as NSString

        switch kind {
        case .markdownTableRow:
            // Insert after the current line.
            let nextLineStart = NSMaxRange(selectedLineRange)
            let range = NSRange(location: nextLineStart, length: 0)
            return (range, "| ")

        case .htmlTableRow:
            // Insert after the current line.
            let nextLineStart = NSMaxRange(selectedLineRange)
            return (NSRange(location: nextLineStart, length: 0), "<tr><td>")

        case .asciiTableRow:
            let nextLineStart = NSMaxRange(selectedLineRange)
            return (NSRange(location: nextLineStart, length: 0), "| ")

        case .markdownBlockquote:
            // Find the end of the contiguous blockquote block.
            var scanOffset = NSMaxRange(selectedLineRange)
            while scanOffset < text.utf16.count {
                let lineRange = nsText.lineRange(for: NSRange(location: scanOffset, length: 0))
                let line = nsText.substring(with: lineRange).trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if line.hasPrefix(">") || line.isEmpty {
                    scanOffset = NSMaxRange(lineRange)
                } else {
                    break
                }
            }
            return (NSRange(location: scanOffset, length: 0), "> ")

        case .htmlListItem:
            let afterClose = findEndOfHTMLTag(
                text: text, after: selectedLineRange.location, tag: "</li>")
            return (NSRange(location: afterClose, length: 0), "<li>")

        case .fencedCodeBlock:
            let afterFence = findEndOfFence(text: text, after: selectedLineRange.location)
            return (NSRange(location: afterFence, length: 0), "```\n")

        case .htmlCodeBlock:
            let afterPre = findEndOfHTMLTag(
                text: text, after: selectedLineRange.location, tag: "</pre>")
            return (NSRange(location: afterPre, length: 0), "<pre><code>\n")

        case .asciiBoxRegion:
            // Insert before the closing border line.
            return findASCIIBoxInsertionPoint(text: text, after: selectedLineRange.location)
        }
    }

    private func findEndOfFence(text: String, after offset: Int) -> Int {
        let nsText = text as NSString
        let searchText = nsText.substring(from: offset)
        if let fenceRange = searchText.range(of: "```") {
            let distance = searchText.distance(
                from: searchText.startIndex, to: fenceRange.upperBound)
            return offset + distance
        }
        return offset
    }

    private func findEndOfHTMLTag(text: String, after offset: Int, tag: String) -> Int {
        let nsText = text as NSString
        let searchText = nsText.substring(from: offset)
        if let tagRange = searchText.range(of: tag, options: .caseInsensitive) {
            let distance = searchText.distance(from: searchText.startIndex, to: tagRange.upperBound)
            return offset + distance
        }
        return offset
    }

    private func findASCIIBoxInsertionPoint(text: String, after offset: Int) -> (
        range: NSRange, prefix: String
    ) {
        let nsText = text as NSString
        let searchText = nsText.substring(from: offset)
        let lines = searchText.components(separatedBy: .newlines)
        var lineStart = offset
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Detect a closing border: contains box-drawing chars but no text content.
            let hasBoxDraw =
                trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "╚╝╩╣╠╦╗╔")) != nil
            if hasBoxDraw
                || (trimmed.hasPrefix("╚") || trimmed.hasPrefix("└") || trimmed.hasPrefix("╰"))
            {
                return (NSRange(location: lineStart, length: 0), "│ ")
            }
            lineStart += line.utf16.count + 1
        }
        return (NSRange(location: offset, length: 0), "")
    }
}
