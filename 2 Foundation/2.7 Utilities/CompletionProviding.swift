import Foundation

// MARK: - Completion Query

/// A content-agnostic query that the editor sends to a completion provider (Foundation 2.7, SR-1).
///
/// The caller fills in the target language, the word prefix at the cursor, and optional
/// context. The concrete provider (module 9) uses this to look up candidates without the
/// editor needing to know about any specific corpus.
public struct CompletionQuery: Sendable {
    /// The language/mode for which completions are requested.
    public let language: WritingAssistLanguage
    /// The partial word at the cursor (already extracted by the caller).
    public let prefix: String
    /// Full document text — available for context-aware providers.
    public let fullText: String
    /// UTF-16 cursor offset within `fullText`.
    public let cursorOffset: Int
    /// Maximum number of results to return.
    public let limit: Int

    public init(
        language: WritingAssistLanguage,
        prefix: String,
        fullText: String = "",
        cursorOffset: Int = 0,
        limit: Int = 5
    ) {
        self.language     = language
        self.prefix       = prefix
        self.fullText     = fullText
        self.cursorOffset = cursorOffset
        self.limit        = limit
    }
}

// MARK: - Completion Provider Protocol

/// Content-agnostic seam between the editor (module 3) and the completion corpus (module 9).
///
/// Foundation owns this protocol (SR-1). Module 9 provides the one concrete type
/// (`SputnikCompletionCorpus`). Language providers in module 3 depend only on this
/// protocol and never import module 9 directly.
///
/// Conforming types must be `Sendable` so they can be called across actor boundaries.
public protocol CompletionProviding: Sendable {
    /// Returns up to `query.limit` completion strings whose lower-cased form starts
    /// with `query.prefix`. Empty array when the language has no corpus or prefix is
    /// too short.
    func completions(_ query: CompletionQuery) async -> [String]
}
