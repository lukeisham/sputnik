import Foundation
import SwiftUI
import FoundationModule

// MARK: - Source

/// The source panel that triggered a context-sensitive grammar lookup.
public enum GrammarHelpSource: Sendable {
    case editor
    case markdownPreview
    case htmlPreview
}

// MARK: - Lookup Result

/// The result of a context-sensitive grammar lookup.
///
/// When a queried word matches multiple topics (e.g. "run" matches both verb-tense
/// and a usage topic), `primaryTopic` holds the best-scoring match and `alternatives`
/// holds the rest for a "See also" list.
public struct GrammarHelpLookupResult: Sendable {
    /// The best-matching topic for the queried word.
    public let primaryTopic: GrammarHelpContent
    /// Other topics that also matched (for "See also" listing).
    public let alternatives: [GrammarHelpContent]
    /// The source panel that triggered the lookup.
    public let source: GrammarHelpSource
}

// MARK: - Coordinator

/// Coordinates context-sensitive Grammar Help lookups from the editor and preview panels.
///
/// The Grammar Help coordinator is unique among help modules: it accepts lookup requests
/// from BOTH `.editor` and `.markdownPreview` sources (dual-panel lookup). It searches
/// the `GrammarHelpIndex` by title and `searchTerms`, and when a word maps to multiple
/// topics, returns the top match with a "See also" list of alternatives.
///
/// Usage from the editor or Markdown preview:
/// ```swift
/// let result = await GrammarHelpCoordinator.shared.lookup(
///     word: "their",
///     source: .editor
/// )
/// // result.primaryTopic → the Their/There/They're topic
/// // result.alternatives → related homophone topics
/// ```
@MainActor
public final class GrammarHelpCoordinator: ObservableObject {

    public static let shared = GrammarHelpCoordinator()

    /// The most recent lookup result, or `nil` if no lookup has been performed yet
    /// or the last lookup returned no matches.
    @Published public private(set) var lastResult: GrammarHelpLookupResult?

    private let index = GrammarHelpIndex.shared

    private init() {}

    // MARK: - Navigation

    /// Called when a help topic should be opened. Assign a closure that writes to
    /// `AppState.requestedHelpTarget`; capture `AppState` weakly to avoid a retain cycle.
    public var onNavigate: ((HelpRequest) -> Void)?

    // MARK: - Public API

    /// Performs a context-sensitive lookup for the given word from the specified source.
    ///
    /// The lookup searches `GrammarHelpIndex` by both title and `searchTerms` using
    /// `searchByTerm(_:)`, which scores matches: exact search-term hits rank highest,
    /// followed by substring matches, and finally title matches. When a word matches
    /// multiple topics, the highest-scoring match becomes `primaryTopic` and the
    /// rest become `alternatives`.
    ///
    /// - Parameters:
    ///   - word: The word or phrase to look up (e.g. "their", "run", "its").
    ///   - source: The panel that initiated the lookup (`.editor` or `.markdownPreview`).
    /// - Returns: A `GrammarHelpLookupResult` with the primary topic and alternatives,
    ///            or `nil` if no topic matched the word.
    @discardableResult
    public func lookup(word: String, source: GrammarHelpSource) async -> GrammarHelpLookupResult? {
        let matches = await index.searchByTerm(word)

        guard let primary = matches.first else {
            lastResult = nil
            return nil
        }

        let result = GrammarHelpLookupResult(
            primaryTopic: primary,
            alternatives: Array(matches.dropFirst()),
            source: source
        )
        lastResult = result
        return result
    }

    /// Opens the Grammar Help panel to a specific topic by its ID.
    ///
    /// - Parameter topicID: The ID of the topic to open (e.g. `"spelling/their-there-theyre"`).
    public func openHelp(for topicID: String) async {
        guard let topic = await index.topic(id: topicID) else { return }
        onNavigate?(HelpRequest(kind: .grammar, topicID: topic.id))
    }

    /// Opens the Grammar Help panel to the primary topic from the last lookup result,
    /// if one exists.
    public func openLastResult() async {
        guard let topicID = lastResult?.primaryTopic.id else { return }
        await openHelp(for: topicID)
    }

    /// Returns all "See also" topic IDs from the last lookup result.
    /// Convenience accessor for UI that wants to display a related-topics list.
    public var alternativeTopicIDs: [String] {
        lastResult?.alternatives.map(\.id) ?? []
    }
}

