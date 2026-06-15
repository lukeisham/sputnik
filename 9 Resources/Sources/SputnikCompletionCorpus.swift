import Foundation
import FoundationModule

// MARK: - Bundle-local decodable types

private struct CompletionEntry: Codable, Sendable {
    let text: String
    let weight: Int
}

private struct CompletionsFile: Codable, Sendable {
    let completions: [CompletionEntry]
}

// MARK: - SputnikCompletionCorpus

/// The concrete `CompletionProviding` implementation for Sputnik (module 9).
///
/// Lazily loads one `*_completions.json` per supported language on first use and
/// builds a weight-sorted prefix index from it. Spelling and Grammar have no corpus
/// here (Spelling completions come from `NSSpellChecker` in module 3.5; Grammar has
/// no Auto-Complete per the applicability matrix). JSON uses `9.7 JSON Help/json_completions.json`.
///
/// **RAM:** Each index is loaded once and held for the app's lifetime — the lists are
/// compact (≤ 60 entries each) so the total resident cost is negligible.
public actor SputnikCompletionCorpus: CompletionProviding {

    private var markdownIndex: [String]?
    private var htmlIndex: [String]?
    private var jsonIndex: [String]?
    private var asciiIndex: [String]?

    public init() {}

    // MARK: - CompletionProviding

    public func completions(_ query: CompletionQuery) async -> [String] {
        let prefix = query.prefix
        guard prefix.count >= 2 else { return [] }

        switch query.language {
        case .spelling, .grammar:
            return []
        case .markdown:
            return prefixMatches(in: loadMarkdown(), prefix: prefix, limit: query.limit)
        case .html:
            return prefixMatches(in: loadHTML(), prefix: prefix, limit: query.limit)
        case .json:
            return prefixMatches(in: loadJSON(), prefix: prefix, limit: query.limit)
        case .asciiArt:
            return prefixMatches(in: loadASCII(), prefix: prefix, limit: query.limit)
        }
    }

    // MARK: - Lazy loaders

    private func loadMarkdown() -> [String] {
        if let idx = markdownIndex { return idx }
        let idx =
            loadBundle(resource: "markdown_completions", subdirectory: "9.3 Markdown Help") ?? []
        markdownIndex = idx
        return idx
    }

    private func loadHTML() -> [String] {
        if let idx = htmlIndex { return idx }
        let idx = loadBundle(resource: "html_completions", subdirectory: "9.4 Html Help") ?? []
        htmlIndex = idx
        return idx
    }

    private func loadJSON() -> [String] {
        if let idx = jsonIndex { return idx }
        let idx = loadBundle(resource: "json_completions", subdirectory: "9.7 JSON Help") ?? []
        jsonIndex = idx
        return idx
    }

    private func loadASCII() -> [String] {
        if let idx = asciiIndex { return idx }
        let idx =
            loadBundle(resource: "ascii_completions", subdirectory: "9.2 ASCII art Help") ?? []
        asciiIndex = idx
        return idx
    }

    // MARK: - Private helpers

    private func loadBundle(resource: String, subdirectory: String? = nil) -> [String]? {
        guard
            let url = Bundle.module.url(
                forResource: resource, withExtension: "json", subdirectory: subdirectory),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(CompletionsFile.self, from: data)
        else { return nil }
        return file.completions
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.text < $1.text }
            .map(\.text)
    }

    /// Returns entries whose lower-cased form starts with `prefix` (case-insensitive),
    /// excluding an exact match (only completions, not confirmations).
    private func prefixMatches(in index: [String], prefix: String, limit: Int) -> [String] {
        let low = prefix.lowercased()
        return Array(
            index.lazy
                .filter { $0.lowercased().hasPrefix(low) && $0.lowercased() != low }
                .prefix(limit)
        )
    }
}
