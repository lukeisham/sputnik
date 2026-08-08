import Foundation
import FoundationModule
import SwiftUI

// MARK: - Source

/// The source panel that triggered a context-sensitive style lookup.
public enum StyleHelpSource: Sendable {
    case editor
    case markdownPreview
    case htmlPreview
}

// MARK: - Lookup Result

/// The result of a context-sensitive style lookup.
public struct StyleHelpLookupResult: Sendable {
    /// The best-matching topic for the queried word.
    public let primaryTopic: StyleHelpContent
    /// Other topics that also matched (for "See also" listing).
    public let alternatives: [StyleHelpContent]
    /// The source panel that triggered the lookup.
    public let source: StyleHelpSource
}

// MARK: - Coordinator

/// Coordinates context-sensitive Style Help lookups from the editor and preview panels.
///
/// All lookups are lexical — Style Help has no structural-vs-lexical distinction.
/// It searches `StyleHelpIndex` by title and `searchTerms`.
@MainActor
public final class StyleHelpCoordinator: ObservableObject {

    public static let shared = StyleHelpCoordinator()

    /// The most recent lookup result, or `nil` if no lookup has been performed yet.
    @Published public private(set) var lastResult: StyleHelpLookupResult?

    private let index = StyleHelpIndex.shared

    private init() {}

    // MARK: - Navigation

    /// Called when a help topic should be opened.
    public var onNavigate: ((HelpRequest) -> Void)?

    // MARK: - Public API

    /// Performs a context-sensitive lookup for the given word from the specified source.
    @discardableResult
    public func lookup(
        word: String,
        source: StyleHelpSource
    ) async -> StyleHelpLookupResult? {
        let matches = await index.searchByTerm(word)

        guard let primary = matches.first else {
            lastResult = nil
            return nil
        }

        let result = StyleHelpLookupResult(
            primaryTopic: primary,
            alternatives: Array(matches.dropFirst()),
            source: source
        )
        lastResult = result
        return result
    }

    /// Opens the Style Help panel to a specific topic by its ID.
    public func openHelp(for topicID: String) async {
        guard let topic = await index.topic(id: topicID) else { return }
        onNavigate?(HelpRequest(kind: .style, topicID: topic.id))
    }

    /// Opens the Style Help panel to the primary topic from the last lookup result.
    public func openLastResult() async {
        guard let topicID = lastResult?.primaryTopic.id else { return }
        await openHelp(for: topicID)
    }

    /// Returns all "See also" topic IDs from the last lookup result.
    public var alternativeTopicIDs: [String] {
        lastResult?.alternatives.map(\.id) ?? []
    }
}
