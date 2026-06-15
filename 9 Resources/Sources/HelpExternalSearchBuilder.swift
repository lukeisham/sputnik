import Foundation
import FoundationModule

/// Generates 0–2 Google search links for a help topic.
///
/// All URL construction goes through `URLComponents` so percent-encoding is always correct
/// and no force-unwrap on `URL` is needed — a nil result yields an empty list (SR-2).
public enum HelpExternalSearchBuilder {

    // MARK: - Public API

    /// Returns 0–2 `HelpExternalSearch` values for the given topic and help kind.
    ///
    /// - Link 1: `"<title>" <contextWord>` — always present when a valid URL can be formed.
    /// - Link 2: first distinct `searchTerm` appended with the context word and "examples" —
    ///   only included when a searchTerm differs from the title.
    /// - Returns `[]` when `helpKind` is `.sputnik` (no meaningful context word and no
    ///   external-search scenario) or when URL construction fails.
    public static func build(
        title: String,
        searchTerms: [String],
        kind: HelpTopic
    ) -> [HelpExternalSearch] {
        let context = contextWord(for: kind)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let q1Parts = ["\"\(title)\"", context].filter { !$0.isEmpty }
        let q1 = q1Parts.joined(separator: " ")
        guard let url1 = googleSearchURL(query: q1) else { return [] }

        let labelSuffix = context.isEmpty ? "" : " \(context)"
        var results: [HelpExternalSearch] = [
            HelpExternalSearch(
                label: "Search the web for \"\(title)\"\(labelSuffix)",
                url: url1
            )
        ]

        // Link 2 — first search term that is meaningfully different from the title
        if let term = searchTerms.first(where: {
            !$0.isEmpty && $0.lowercased() != title.lowercased()
        }) {
            let q2Parts = [term, context].filter { !$0.isEmpty } + ["examples"]
            let q2 = q2Parts.joined(separator: " ")
            if let url2 = googleSearchURL(query: q2) {
                results.append(HelpExternalSearch(
                    label: "Search the web for \(term)\(labelSuffix) examples",
                    url: url2
                ))
            }
        }

        return results
    }

    // MARK: - Internal helpers

    static func contextWord(for kind: HelpTopic) -> String {
        switch kind {
        case .grammar:  return "grammar"
        case .markdown: return "markdown syntax"
        case .html:     return "HTML"
        case .json:     return "JSON"
        case .asciiArt: return "ASCII art"
        case .sputnik:  return ""
        }
    }

    private static func googleSearchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}
