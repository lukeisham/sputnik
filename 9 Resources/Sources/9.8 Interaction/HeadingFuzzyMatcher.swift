import Foundation

/// A deterministic, dependency-free fuzzy heading scorer.
///
/// Blends token overlap (Jaccard), ordered substring containment, and Levenshtein edit
/// distance to produce a 0–1 score. Used as the fallback ranker when no registry
/// definition matches a detected element — lightweight enough for an inline popup.
public enum HeadingFuzzyMatcher {

    /// Scores how well `query` matches `candidate` as a heading.
    /// - Parameters:
    ///   - query: The user's contextual heading text (e.g. "Sentence parser").
    ///   - candidate: The candidate heading text (e.g. "Sentence Parser").
    /// - Returns: A score from 0 (no match) to 1 (exact match).
    public static func score(query: String, candidate: String) -> Double {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let c = candidate.lowercased().trimmingCharacters(in: .whitespaces)

        guard !q.isEmpty, !c.isEmpty else { return 0 }

        // Exact match = 1.0
        if q == c { return 1.0 }

        // Containment: candidate contains query or vice versa
        if c.contains(q) || q.contains(c) {
            return 0.9
        }

        let qTokens = q.split(separator: " ").map(String.init)
        let cTokens = c.split(separator: " ").map(String.init)

        // Jaccard similarity on tokens
        let qSet = Set(qTokens)
        let cSet = Set(cTokens)
        guard !qSet.isEmpty, !cSet.isEmpty else { return 0 }

        let intersection = qSet.intersection(cSet).count
        let union = qSet.union(cSet).count
        let jaccard = Double(intersection) / Double(union)

        // Ordered substring containment: check if query tokens appear in order in candidate
        var ordered = 0.0
        if qTokens.count > 1 {
            var searchIdx = c.startIndex
            for token in qTokens {
                if let found = c[searchIdx...].range(of: token) {
                    searchIdx = found.upperBound
                    ordered += 1.0
                }
            }
            ordered /= Double(qTokens.count)
        }

        // Levenshtein for close typos (e.g. "parsr" → "parser")
        let levScore = 1.0 - (Double(levenshtein(q, c)) / Double(max(q.count, c.count, 1)))

        // Blend: Jaccard (0.5) + ordered containment (0.3) + Levenshtein (0.2)
        return jaccard * 0.5 + ordered * 0.3 + levScore * 0.2
    }

    // MARK: - Levenshtein Distance

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        guard m > 0 else { return n }
        guard n > 0 else { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }
}
