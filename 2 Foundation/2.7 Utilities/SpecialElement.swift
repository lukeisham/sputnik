import Foundation

// MARK: - Special Element Kind

/// The **container** shape of a detected special element — determines how and where
/// content is inserted into the document.
///
/// `kind` is orthogonal to `definitionID`: one container kind (e.g. `markdownTableRow`)
/// can host many semantic elements (`sentence-parser`, `glossary`, …).
public enum SpecialElementKind: String, Codable, Sendable {
    /// A pipe-delimited Markdown table row.
    case markdownTableRow
    /// An HTML `<tr>` row in a `<table>`.
    case htmlTableRow
    /// An ASCII art pipe-delimited table row.
    case asciiTableRow
    /// A Markdown blockquote (`> …`) line.
    case markdownBlockquote
    /// An HTML `<li>` item.
    case htmlListItem
    /// A fenced code block (````` ``` `````).
    case fencedCodeBlock
    /// An HTML `<pre><code>` block.
    case htmlCodeBlock
    /// An ASCII art box-drawn region.
    case asciiBoxRegion
}

// MARK: - Special Element

/// A detected special element at the user's selection.
///
/// Carries both the **container** shape (`kind`) and the **semantic** identity
/// (`definitionID`), plus the two detection signals (`syntaxTerm`, `contextHeading`),
/// source ranges, and insertion metadata.
public struct SpecialElement: Sendable {
    /// The container shape — determines insertion mechanics.
    public let kind: SpecialElementKind
    /// The resolved registry definition id (e.g. `"sentence-parser"`), or `nil`
    /// when only the syntax term matched (generic → fuzzy fallback).
    public let definitionID: String?
    /// The structural signal that fired (e.g. `"table"`, `"blockquote"`, `"code block"`).
    /// Matched against registry `triggers.syntaxTerms`.
    public let syntaxTerm: String
    /// The nearest heading text above the selection (e.g. `"Sentence parser"`),
    /// or `nil` if none found.
    public let contextHeading: String?
    /// The NSRange of the entire detected element in the text.
    public let elementRange: NSRange
    /// The NSRange of the line the selection is on.
    public let selectedLineRange: NSRange
    /// The NSRange where content should be inserted.
    public let insertionRange: NSRange
    /// The formatting prefix for inserted content (e.g. `"| "` for a table row).
    public let insertionPrefix: String

    public init(
        kind: SpecialElementKind,
        definitionID: String?,
        syntaxTerm: String,
        contextHeading: String?,
        elementRange: NSRange,
        selectedLineRange: NSRange,
        insertionRange: NSRange,
        insertionPrefix: String
    ) {
        self.kind = kind
        self.definitionID = definitionID
        self.syntaxTerm = syntaxTerm
        self.contextHeading = contextHeading
        self.elementRange = elementRange
        self.selectedLineRange = selectedLineRange
        self.insertionRange = insertionRange
        self.insertionPrefix = insertionPrefix
    }
}
