import Foundation

// MARK: - ASCII Art Help Coordinator

/// Handles context-sensitive help lookup from the editor.
///
/// When the editor mode is `.asciiArt` and the user right-clicks a word,
/// the app calls `bestMatch(for:)` to search `ASCIIArtHelpIndex` for
/// matching topics. The coordinator also provides `openHelp(for:)` to
/// programmatically open a specific topic.
///
/// All index access happens on the index's actor; results are returned on
/// the caller's isolation domain.
@MainActor
public final class ASCIIArtHelpCoordinator {

    // MARK: - Singleton

    public static let shared = ASCIIArtHelpCoordinator()

    // MARK: - Properties

    /// The panel view this coordinator routes topics into.
    /// Set by the panel on appear; held weakly to avoid retain cycles.
    public weak var panelView: ASCIIArtHelpPanelView?

    /// Callback invoked when a topic should be opened.
    /// The panel view sets this to its own `openTopic(_:)` method.
    public var onOpenTopic: ((String) -> Void)?

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Searches the ASCII Art Help index for the best-matching topic for the
    /// given word.
    ///
    /// The search is case-insensitive and checks against title, category,
    /// search terms, and body text. Returns the most relevant topic, or `nil`
    /// if nothing matches.
    ///
    /// - Parameter word: The word the user right-clicked in the editor.
    /// - Returns: The best-matching topic, or `nil`.
    public func bestMatch(for word: String) async -> ASCIIArtHelpContent? {
        let index = ASCIIArtHelpIndex.shared
        let results = await index.search(query: word)

        guard !results.isEmpty else { return nil }

        // Prefer exact title matches, then category matches, then fall through.
        let wordLower = word.lowercased()

        if let exactTitle = results.first(where: {
            $0.title.lowercased() == wordLower
        }) {
            return exactTitle
        }

        if let exactSearchTerm = results.first(where: { topic in
            topic.searchTerms.contains { $0.lowercased() == wordLower }
        }) {
            return exactSearchTerm
        }

        // Default: return the first result.
        return results.first
    }

    /// Returns all topics that match the given query.
    ///
    /// - Parameter query: A search string.
    /// - Returns: Matching topics, sorted by relevance.
    public func search(query: String) async -> [ASCIIArtHelpContent] {
        let index = ASCIIArtHelpIndex.shared
        return await index.search(query: query)
    }

    /// Opens the help panel to a specific topic.
    ///
    /// - Parameter topicID: The ID of the topic to open (e.g. `"basics/drawing-shapes"`).
    /// - Returns: `true` if the topic was found and opened, `false` otherwise.
    @discardableResult
    public func openHelp(for topicID: String) async -> Bool {
        let index = ASCIIArtHelpIndex.shared
        guard await index.topic(id: topicID) != nil else {
            return false
        }
        onOpenTopic?(topicID)
        return true
    }

    /// Returns all available categories from the help index.
    public func categories() async -> [String] {
        let index = ASCIIArtHelpIndex.shared
        return await index.categories()
    }

    /// Returns all topics in the help index.
    public func allTopics() async -> [ASCIIArtHelpContent] {
        let index = ASCIIArtHelpIndex.shared
        return await index.allTopics()
    }
}
