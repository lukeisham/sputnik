import Foundation
import FoundationModule

/// The concrete help-context resolver that dispatches to the module-9 coordinators.
///
/// This is the orchestration layer (SR-1: module 9 owns orchestration). It conforms to
/// `HelpContextResolving`, which Foundation owns as a protocol, so Foundation never
/// imports or references any module-9 type.
///
/// One instance is created at app assembly and shared across all three hosts (Text Editor,
/// Markdown Preview, HTML Preview).
@MainActor
public final class SputnikHelpContextResolver: HelpContextResolving {

    // MARK: - Singleton

    /// Shared instance. Injected into the three hosts at construction.
    public static let shared = SputnikHelpContextResolver()

    private init() {}

    // MARK: - HelpContextResolving

    /// Resolves the user's text selection to a matching help topic, dispatching to the
    /// appropriate coordinator based on `query.kind`.
    ///
    /// - Parameter query: The context query from a host panel.
    /// - Returns: A `HelpRequest` with the resolved topic ID, or `nil` when no match.
    public func resolve(_ query: HelpContextQuery) async -> HelpRequest? {
        let topicID: String?

        switch query.kind {
        case .grammar:
            let result = await GrammarHelpCoordinator.shared.lookup(
                word: query.selectedText,
                source: .editor
            )
            topicID = result?.primaryTopic.id

        case .markdown:
            topicID = MarkdownHelpCoordinator.shared.lookupContext(
                fullText: query.fullText,
                cursorOffset: query.cursorOffset,
                selectedText: query.selectedText
            )

        case .html:
            topicID = HTMLHelpCoordinator.shared.lookupContext(
                fullText: query.fullText,
                cursorOffset: query.cursorOffset,
                selectedText: query.selectedText
            )

        case .json:
            topicID = JSONHelpCoordinator.shared.lookupContext(
                fullText: query.fullText,
                cursorOffset: query.cursorOffset,
                selectedText: query.selectedText
            )

        case .asciiArt:
            let topic = await ASCIIArtHelpCoordinator.shared.bestMatch(for: query.selectedText)
            topicID = topic?.id

        case .sputnik:
            topicID = nil
        }

        guard let topicID else { return nil }
        return HelpRequest(kind: query.kind, topicID: topicID)
    }
}
