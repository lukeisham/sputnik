import Foundation

/// A single hit-testable issue that the editor underlines and can explain on click.
///
/// A checker writes underline attributes to `NSTextStorage` for presentation, but a
/// click must map a character location back to the issue and its suggested fixes.
/// This value type is that queryable model (one responsibility per file, SR-6).
///
/// Spelling and grammar do not use this type. Apple's `NSTextView` checker draws and
/// handles its own underlines.
public struct EditorAnnotation: Sendable, Equatable {

    /// The checker that produced the annotation.
    public enum Kind: Sendable {
        /// A structural HTML issue (unclosed tag, mismatched tag, unquoted attribute,
        /// duplicate id) produced by `HTMLSyntaxChecker`. Rendered with a blue underline.
        case htmlSyntax
    }

    /// The character range (UTF-16, matching `NSTextStorage`) the issue covers.
    public let range: NSRange

    /// The checker that produced the issue.
    public let kind: Kind

    /// Ordered messages or correction candidates, best first. Can be empty.
    public let suggestions: [String]

    public init(
        range: NSRange,
        kind: Kind,
        suggestions: [String]
    ) {
        self.range = range
        self.kind = kind
        self.suggestions = suggestions
    }
}
