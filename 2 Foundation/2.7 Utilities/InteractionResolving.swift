import Foundation

// MARK: - Interaction Query

/// Carries the full context of the user's selection for interaction resolution.
///
/// Foundation owns this as a cross-module query primitive (SR-1). The host fills
/// all fields from the text system; the provider uses them to decide what resource
/// content to insert.
public struct InteractionQuery: Sendable {
    /// The text the user has selected (or word under cursor).
    public let selectedText: String
    /// The full text of the document or panel content.
    public let fullText: String
    /// The UTF-16 offset of the cursor or selection start.
    public let cursorOffset: Int
    /// The length of the selection in UTF-16 code units.
    public let selectionLength: Int
    /// The resource language for this file mode (markdown, html, asciiArt, …).
    public let fileLanguage: WritingAssistLanguage
    /// The detected special element, if any. Carries the resolved `definitionID`,
    /// `syntaxTerm`, `contextHeading`, and insertion ranges.
    public let detectedElement: SpecialElement?

    public init(
        selectedText: String,
        fullText: String = "",
        cursorOffset: Int = 0,
        selectionLength: Int = 0,
        fileLanguage: WritingAssistLanguage,
        detectedElement: SpecialElement? = nil
    ) {
        self.selectedText = selectedText
        self.fullText = fullText
        self.cursorOffset = cursorOffset
        self.selectionLength = selectionLength
        self.fileLanguage = fileLanguage
        self.detectedElement = detectedElement
    }
}

// MARK: - Interaction Section Item

/// A single section of content to insert, corresponding to one slot (registered element)
/// or one ranked candidate (fuzzy fallback).
public struct InteractionSectionItem: Sendable {
    /// The display title for this section (e.g. "Lexical", "Structural").
    public let sectionTitle: String
    /// A short preview or excerpt shown in the popup.
    public let preview: String
    /// The full content text to insert.
    public let content: String
    /// The resource language this content was sourced from.
    public let resourceLanguage: WritingAssistLanguage
    /// A fuzzy ranking score (0–1), used for ordering and tie-breaks.
    public let matchScore: Double

    public init(
        sectionTitle: String,
        preview: String = "",
        content: String = "",
        resourceLanguage: WritingAssistLanguage,
        matchScore: Double = 0
    ) {
        self.sectionTitle = sectionTitle
        self.preview = preview
        self.content = content
        self.resourceLanguage = resourceLanguage
        self.matchScore = matchScore
    }
}

// MARK: - Interaction Result

/// The result of resolving an interaction query — an ordered list of sections to insert.
public struct InteractionResult: Sendable {
    /// The sections to insert, in template order (registered element) or ranked order (fallback).
    public let sections: [InteractionSectionItem]
    /// A human-readable description of where content will be inserted
    /// (e.g. "New row below", "Append after block").
    public let insertionDescription: String

    public init(sections: [InteractionSectionItem], insertionDescription: String = "") {
        self.sections = sections
        self.insertionDescription = insertionDescription
    }
}

// MARK: - Interaction Providing Protocol

/// The seam for resolving an interaction query into insertable content sections.
///
/// Foundation owns the protocol (SR-1); module 9.8 provides the concrete
/// `InteractionProvider` that dispatches to the registry and resource indexes.
public protocol InteractionProviding: Sendable {
    /// Resolves the user's selection context into insertable content sections.
    /// - Parameter query: The full context of the user's selection.
    /// - Returns: An `InteractionResult` with ordered sections and a description.
    func sections(for query: InteractionQuery) async -> InteractionResult
}

// MARK: - Interaction Inserting Protocol

/// The seam for formatting and inserting an interaction result into the document.
///
/// Foundation owns the protocol (SR-1); module 9.8 provides `ContentInserter`.
@MainActor
public protocol InteractionInserting: Sendable {
    /// Formats and returns the text and insertion range for a single section item.
    /// - Parameters:
    ///   - item: The section item to insert.
    ///   - element: The detected special element (defines container shape).
    ///   - fullText: The full document text (for range calculations).
    /// - Returns: A tuple of the new text to insert and the NSRange to replace.
    func insert(
        _ item: InteractionSectionItem,
        into element: SpecialElement,
        fullText: String
    ) -> (newText: String, insertionRange: NSRange)
}

// MARK: - Special Element Detecting Protocol

/// The seam for detecting a special element in the user's text.
///
/// Foundation owns the protocol (SR-1) so the unified menu helper in
/// `SelectionContextMenu` can run detection without importing module 9.
/// Module 9.8 provides the concrete `SpecialElementDetector`.
@MainActor
public protocol SpecialElementDetecting: AnyObject {
    /// Detects a special element at the user's selection.
    /// - Parameters:
    ///   - text: The full document text.
    ///   - selectedRange: The current selection NSRange.
    ///   - language: The resource/writing-assist language.
    /// - Returns: A `SpecialElement` if detected, or `nil`.
    func detect(in text: String, selectedRange: NSRange, language: WritingAssistLanguage)
        -> SpecialElement?
}
