import Foundation
import FoundationModule

/// Formats interaction result sections into document content, keyed by the special
/// element's container kind.
///
/// `@MainActor` because it produces text that the host writes to `NSTextView` via
/// `insertText(_:replacementRange:)` — never direct string mutation (SR-2, undo-safe).
@MainActor
public final class ContentInserter: InteractionInserting {

    public init() {}

    // MARK: - Template Insert (Auto-fill Path)

    /// Inserts every section from the result as a contiguous block.
    /// - Parameters:
    ///   - result: The interaction result with one or more sections.
    ///   - element: The detected special element (defines container shape).
    ///   - fullText: The full document text (for range calculations).
    /// - Returns: The combined text to insert and the insertion range.
    public func insertTemplate(
        _ result: InteractionResult,
        into element: SpecialElement,
        fullText: String
    ) -> (newText: String, insertionRange: NSRange) {
        let lines = result.sections.map { item in
            formatSection(item, for: element.kind, prefix: element.insertionPrefix)
        }

        let newText = lines.joined(separator: "\n") + "\n"
        return (newText, element.insertionRange)
    }

    // MARK: - Single Section Insert (Fallback Path)

    /// Formats and returns the text for a single chosen section.
    public func insert(
        _ item: InteractionSectionItem,
        into element: SpecialElement,
        fullText: String
    ) -> (newText: String, insertionRange: NSRange) {
        let line = formatSection(item, for: element.kind, prefix: element.insertionPrefix)
        let newText = line + "\n"
        return (newText, element.insertionRange)
    }

    // MARK: - Per-Container Formatting

    /// Formats a single section item into a line matching the container shape.
    private func formatSection(
        _ item: InteractionSectionItem,
        for kind: SpecialElementKind,
        prefix: String
    ) -> String {
        let content = item.content.isEmpty ? "_(fill in)_" : item.content

        switch kind {
        case .markdownTableRow:
            // Collapse content into a pipe-delimited row.
            let escaped = content.replacingOccurrences(of: "\n", with: " ")
            return "| \(item.sectionTitle) | \(escaped) |"

        case .asciiTableRow:
            let escaped = content.replacingOccurrences(of: "\n", with: " ")
            return "| \(item.sectionTitle) | \(escaped) |"

        case .htmlTableRow:
            let escaped = content.replacingOccurrences(of: "\n", with: "<br>")
            return "<tr><td>\(item.sectionTitle)</td><td>\(escaped)</td></tr>"

        case .markdownBlockquote:
            let lines = content.components(separatedBy: .newlines)
            return lines.map { "> **\(item.sectionTitle):** \($0)" }.joined(separator: "\n")

        case .htmlListItem:
            return "<li><strong>\(item.sectionTitle):</strong> \(content)</li>"

        case .fencedCodeBlock:
            return "```\n// \(item.sectionTitle)\n\(content)\n```"

        case .htmlCodeBlock:
            let escaped =
                content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<pre><code>// \(item.sectionTitle)\n\(escaped)\n</code></pre>"

        case .asciiBoxRegion:
            let lines = content.components(separatedBy: .newlines)
            return lines.map { "\(prefix)\($0)" }.joined(separator: "\n")
        }
    }
}
