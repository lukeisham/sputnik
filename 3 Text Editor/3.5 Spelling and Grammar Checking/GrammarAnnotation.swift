import Foundation

/// A single hit-testable spelling or grammar issue produced by `SpellingGrammarChecker`.
///
/// The checker writes underline attributes to `NSTextStorage` for presentation, but a
/// click needs to map a character location back to the issue and its suggested fixes.
/// This value type is that queryable model (one responsibility per file, SR-6).
///
/// `isSuppressed` marks a grammar issue that overlaps a spelling issue: it is kept in the
/// model but **not** rendered, so the red spelling underline takes precedence. Once the
/// overlapping spelling issue is fixed or dismissed, a re-check clears the suppression and
/// the grammar underline surfaces.
public struct GrammarAnnotation: Sendable, Equatable {

    /// Whether the annotation came from spelling or grammar checking.
    public enum Kind: Sendable {
        case spelling
        case grammar
    }

    /// The character range (UTF-16, matching `NSTextStorage`) the issue covers.
    public let range: NSRange

    /// Whether this is a spelling or grammar issue.
    public let kind: Kind

    /// Ordered correction candidates, best first. May be empty for grammar issues that
    /// carry only a description.
    public let suggestions: [String]

    /// `true` when a grammar issue overlaps a spelling issue and is therefore hidden
    /// beneath the red spelling underline. Always `false` for spelling annotations.
    public let isSuppressed: Bool

    public init(
        range: NSRange,
        kind: Kind,
        suggestions: [String],
        isSuppressed: Bool = false
    ) {
        self.range = range
        self.kind = kind
        self.suggestions = suggestions
        self.isSuppressed = isSuppressed
    }
}
