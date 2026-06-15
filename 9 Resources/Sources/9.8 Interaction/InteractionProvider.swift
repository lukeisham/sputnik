import Foundation
import FoundationModule

/// Registry-driven interaction provider: resolves a query by walking registry slots
/// and filling each `resource` slot from the named index lookup.
///
/// Falls back to `ResourceSectionIndex` + `HeadingFuzzyMatcher` when the detected
/// element has no registry definition.
public actor InteractionProvider: InteractionProviding {

    private let registry: SpecialElementRegistry
    private let sectionIndex: ResourceSectionIndex

    public init(
        registry: SpecialElementRegistry = .shared,
        sectionIndex: ResourceSectionIndex = .shared
    ) {
        self.registry = registry
        self.sectionIndex = sectionIndex
    }

    // MARK: - InteractionProviding

    public func sections(for query: InteractionQuery) async -> InteractionResult {
        guard let element = query.detectedElement else {
            return InteractionResult(sections: [], insertionDescription: "No element detected")
        }

        if let definitionID = element.definitionID,
            let definition = await registry.definition(id: definitionID)
        {
            return await primaryPath(definition: definition, query: query, element: element)
        }

        return await fallbackPath(element: element, query: query)
    }

    // MARK: - Primary Path (Registered Element)

    private func primaryPath(
        definition: SpecialElementDefinition,
        query: InteractionQuery,
        element: SpecialElement
    ) async -> InteractionResult {
        var sections: [InteractionSectionItem] = []

        for slot in definition.slots {
            let item: InteractionSectionItem
            switch slot.source {
            case .userContent:
                item = InteractionSectionItem(
                    sectionTitle: slot.label,
                    preview: "",
                    content: "",
                    resourceLanguage: definition.resourceLanguage,
                    matchScore: 0
                )

            case .resource(let lookup):
                let results = await performLookup(lookup, selection: query.selectedText)
                if let best = results.first {
                    item = InteractionSectionItem(
                        sectionTitle: slot.label,
                        preview: String(best.preview.prefix(80)),
                        content: best.content,
                        resourceLanguage: definition.resourceLanguage,
                        matchScore: best.score
                    )
                } else {
                    // No match — skip this slot entirely (SR-2).
                    continue
                }
            }
            sections.append(item)
        }

        return InteractionResult(
            sections: sections,
            insertionDescription: definition.displayName
        )
    }

    // MARK: - Fallback Path (Unregistered Element)

    private func fallbackPath(element: SpecialElement, query: InteractionQuery) async
        -> InteractionResult
    {
        // Determine candidate language from element kind.
        let language = languageForKind(element.kind)

        let allSections = await sectionIndex.sections(for: language)

        // Build a weighted query: contextHeading + syntaxTerm + selectedText.
        let queryParts = [
            element.contextHeading,
            element.syntaxTerm,
            query.selectedText,
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let queryText = queryParts.joined(separator: " ")

        guard !queryText.isEmpty else {
            return InteractionResult(sections: [], insertionDescription: "No context available")
        }

        // Score each section against the query.
        var scored: [(section: ResourceSectionIndex.ResourceSection, score: Double)] = []
        for section in allSections {
            let headingScore = HeadingFuzzyMatcher.score(
                query: queryText, candidate: section.heading)
            let bodyScore = HeadingFuzzyMatcher.score(
                query: queryText, candidate: section.sectionBody)
            // Blend: heading (0.6) + body (0.4), then multiply by 0.6 since this is fuzzy fallback
            let combined = (headingScore * 0.6 + bodyScore * 0.4) * 0.6
            if combined > 0.2 {  // Score floor — drop weak matches.
                scored.append((section, combined))
            }
        }

        let ranked = scored.sorted { $0.score > $1.score }.prefix(8)

        let items = ranked.map { scorePair in
            InteractionSectionItem(
                sectionTitle: scorePair.section.heading,
                preview: String(scorePair.section.sectionBody.prefix(80)),
                content: scorePair.section.sectionBody,
                resourceLanguage: language,
                matchScore: scorePair.score
            )
        }

        return InteractionResult(
            sections: Array(items),
            insertionDescription: "Suggested content"
        )
    }

    // MARK: - Resource Lookup Dispatch

    /// Performs a named resource lookup against the existing index.
    /// Returns up to 3 scored results with content and preview.
    private func performLookup(_ lookup: ResourceLookup, selection: String) async -> [(
        content: String, preview: String, score: Double
    )] {
        switch lookup {
        case .lexicalDefinition:
            let topics = await GrammarHelpIndex.shared.searchByTerm(
                selection, preferStructural: false)
            return topics.prefix(3).map { t in
                (content: t.body, preview: t.title, score: 0.8)
            }

        case .structuralAnalysis:
            let topics = await GrammarHelpIndex.shared.searchByTerm(
                selection, preferStructural: true)
            return topics.prefix(3).map { t in
                (content: t.body, preview: t.title, score: 0.8)
            }

        case .markdownTopic:
            let topics = await MarkdownHelpIndex.shared.search(query: selection)
            return topics.prefix(3).map { t in
                (content: t.body, preview: t.title, score: 0.7)
            }

        case .htmlTopic:
            let topics = await HTMLHelpIndex.shared.search(query: selection)
            return topics.prefix(3).map { t in
                (content: t.body, preview: t.title, score: 0.7)
            }

        case .asciiTopic:
            let topics = await ASCIIArtHelpIndex.shared.search(query: selection)
            return topics.prefix(3).map { t in
                (content: t.body, preview: t.title, score: 0.7)
            }

        case .jsonTopic:
            let topics = await JSONHelpIndex.shared.search(query: selection)
            return topics.prefix(3).map { t in
                (content: t.body, preview: t.title, score: 0.7)
            }
        }
    }

    // MARK: - Helpers

    private func languageForKind(_ kind: SpecialElementKind) -> WritingAssistLanguage {
        switch kind {
        case .markdownTableRow, .markdownBlockquote, .fencedCodeBlock:
            return .markdown
        case .htmlTableRow, .htmlListItem, .htmlCodeBlock:
            return .html
        case .asciiTableRow, .asciiBoxRegion:
            return .asciiArt
        }
    }
}
