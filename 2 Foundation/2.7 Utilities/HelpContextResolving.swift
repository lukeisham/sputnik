import Foundation

// MARK: - Help Context Query

/// A value type describing the user's current selection and context in a text-display panel.
///
/// Foundation owns this as a content-agnostic query primitive (SR-1). The caller fills
/// the kind, selected text, full document text, and cursor offset; the resolver uses
/// this to match against a help topic. Only the kind and selectedText are required;
/// fullText and cursorOffset provide additional context for syntax-aware matching.
public struct HelpContextQuery: Sendable, Equatable {
    /// Which help panel to target.
    public let kind: HelpTopic
    /// The text the user has selected (or the word under the cursor).
    public let selectedText: String
    /// The full text of the document or panel content, for syntax-aware matching.
    public let fullText: String
    /// The UTF-16 offset of the cursor or selection start.
    public let cursorOffset: Int
    /// The length of the selection in UTF-16 code units (default 0 for cursor-only).
    /// Used by grammar help to detect multi-word selections and prioritize structural topics.
    public let selectionLength: Int

    /// Creates a help context query.
    /// - Parameters:
    ///   - kind: The help panel kind.
    ///   - selectedText: The user's selected text.
    ///   - fullText: The full document text (default empty).
    ///   - cursorOffset: The cursor offset (default 0).
    ///   - selectionLength: The length of the selection (default 0).
    public init(
        kind: HelpTopic,
        selectedText: String,
        fullText: String = "",
        cursorOffset: Int = 0,
        selectionLength: Int = 0
    ) {
        self.kind = kind
        self.selectedText = selectedText
        self.fullText = fullText
        self.cursorOffset = cursorOffset
        self.selectionLength = selectionLength
    }
}

// MARK: - Help Context Resolver Protocol

/// A content-agnostic seam for resolving a user's text selection to a help topic.
///
/// Foundation owns this protocol (SR-1) — it knows nothing about concrete help
/// coordinators in module 9. Module 9 provides the concrete resolver that dispatches
/// to `GrammarHelpCoordinator`, `MarkdownHelpCoordinator`, `HTMLHelpCoordinator`,
/// and `ASCIIArtHelpCoordinator`.
///
/// Conforming types must be `Sendable` so they can be invoked from a `Task` without
/// actor-isolation violations.
public protocol HelpContextResolving: Sendable {
    /// Resolves the user's selected text and context to a matching help topic.
    ///
    /// - Parameter query: The context query containing the selected text, full text,
    ///   cursor offset, and the target help kind.
    /// - Returns: A `HelpRequest` describing the panel to reveal and the topic to
    ///   navigate to, or `nil` when no match is found.
    func resolve(_ query: HelpContextQuery) async -> HelpRequest?
}
