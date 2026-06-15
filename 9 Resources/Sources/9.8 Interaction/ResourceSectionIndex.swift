import Foundation
import FoundationModule

/// Flattens resource topics into sections keyed by heading (topic title, `##`/`###` sub-headings).
///
/// Used only by the fallback path (unregistered elements). Grammar and Markdown topics
/// are parsed for body sub-headings; HTML/ASCII/JSON topics fall back to title + `searchTerms`.
/// Cached per language for app lifetime.
public actor ResourceSectionIndex {

    // MARK: - Types

    /// A single section extracted from a resource topic.
    public struct ResourceSection: Sendable {
        /// The topic id this section belongs to.
        public let topicID: String
        /// The section heading text (topic title or sub-heading).
        public let heading: String
        /// The section body content.
        public let sectionBody: String
        /// The resource language.
        public let resourceLanguage: WritingAssistLanguage
    }

    // MARK: - Singleton

    public static let shared = ResourceSectionIndex()

    // MARK: - State

    private var cache: [WritingAssistLanguage: [ResourceSection]] = [:]
    private var didLoad: Set<WritingAssistLanguage> = []

    private init() {}

    // MARK: - Public API

    /// Returns all sections for the given resource language.
    public func sections(for language: WritingAssistLanguage) async -> [ResourceSection] {
        if !didLoad.contains(language) {
            await load(language)
        }
        return cache[language] ?? []
    }

    // MARK: - Loading

    private func load(_ language: WritingAssistLanguage) async {
        didLoad.insert(language)

        switch language {
        case .grammar:
            let topics = await GrammarHelpIndex.shared.allTopics()
            cache[language] = topics.flatMap { flattenGrammarTopic($0) }

        case .markdown:
            let topics = await MarkdownHelpIndex.shared.allTopics()
            cache[language] = topics.flatMap { flattenMarkdownTopic($0) }

        case .html:
            let topics = await HTMLHelpIndex.shared.allTopics()
            cache[language] = topics.flatMap { flattenGenericTopic($0, language: .html) }

        case .asciiArt:
            let topics = await ASCIIArtHelpIndex.shared.allTopics()
            cache[language] = topics.flatMap { flattenASCIITopic($0) }

        case .json:
            let topics = await JSONHelpIndex.shared.allTopics()
            cache[language] = topics.flatMap { flattenGenericTopic($0, language: .json) }

        case .spelling:
            // Spelling has no index; no sections.
            cache[language] = []
        }
    }

    // MARK: - Flattening Helpers

    private func flattenGrammarTopic(_ topic: GrammarHelpContent) -> [ResourceSection] {
        var sections: [ResourceSection] = []

        // Topic title as a section.
        sections.append(
            ResourceSection(
                topicID: topic.id,
                heading: topic.title,
                sectionBody: topic.body,
                resourceLanguage: .grammar
            ))

        // Parse body for ## or ### sub-headings.
        let lines = topic.body.components(separatedBy: .newlines)
        var currentHeading: String?
        var currentBody: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                if let h = currentHeading {
                    sections.append(
                        ResourceSection(
                            topicID: topic.id,
                            heading: h,
                            sectionBody: currentBody.joined(separator: "\n").trimmingCharacters(
                                in: .whitespacesAndNewlines),
                            resourceLanguage: .grammar
                        ))
                }
                currentHeading = trimmed.trimmingCharacters(
                    in: CharacterSet(charactersIn: "#").union(.whitespaces))
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        if let h = currentHeading {
            sections.append(
                ResourceSection(
                    topicID: topic.id,
                    heading: h,
                    sectionBody: currentBody.joined(separator: "\n").trimmingCharacters(
                        in: .whitespacesAndNewlines),
                    resourceLanguage: .grammar
                ))
        }

        return sections
    }

    private func flattenMarkdownTopic(_ topic: MarkdownHelpContent) -> [ResourceSection] {
        var sections: [ResourceSection] = []
        sections.append(
            ResourceSection(
                topicID: topic.id,
                heading: topic.title,
                sectionBody: topic.body,
                resourceLanguage: .markdown
            ))
        // Parse sub-headings.
        let lines = topic.body.components(separatedBy: .newlines)
        var currentHeading: String?
        var currentBody: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                if let h = currentHeading {
                    sections.append(
                        ResourceSection(
                            topicID: topic.id,
                            heading: h,
                            sectionBody: currentBody.joined(separator: "\n").trimmingCharacters(
                                in: .whitespacesAndNewlines),
                            resourceLanguage: .markdown
                        ))
                }
                currentHeading = trimmed.trimmingCharacters(
                    in: CharacterSet(charactersIn: "#").union(.whitespaces))
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        if let h = currentHeading {
            sections.append(
                ResourceSection(
                    topicID: topic.id,
                    heading: h,
                    sectionBody: currentBody.joined(separator: "\n").trimmingCharacters(
                        in: .whitespacesAndNewlines),
                    resourceLanguage: .markdown
                ))
        }
        return sections
    }

    private func flattenGenericTopic(
        _ topic: any HelpTopicCommon, language: WritingAssistLanguage
    ) -> [ResourceSection] {
        return [
            ResourceSection(
                topicID: topic.id,
                heading: topic.title,
                sectionBody: topic.searchTerms.joined(separator: ", "),
                resourceLanguage: language
            )
        ]
    }

    private func flattenASCIITopic(_ topic: ASCIIArtHelpContent) -> [ResourceSection] {
        return [
            ResourceSection(
                topicID: topic.id,
                heading: topic.title,
                sectionBody: topic.body,
                resourceLanguage: .asciiArt
            )
        ]
    }
}

// MARK: - HelpTopicCommon (shared protocol for topic content)

/// Minimal protocol so ResourceSectionIndex can work with all topic types generically.
public protocol HelpTopicCommon: Sendable {
    var id: String { get }
    var title: String { get }
    var searchTerms: [String] { get }
}

extension GrammarHelpContent: HelpTopicCommon {}
extension MarkdownHelpContent: HelpTopicCommon {}
extension HTMLHelpContent: HelpTopicCommon {}
extension ASCIIArtHelpContent: HelpTopicCommon {}
extension JSONHelpContent: HelpTopicCommon {}
