import Foundation
import NaturalLanguage

/// Performs extractive summarization on a body of text using term-frequency sentence scoring.
///
/// The algorithm tokenizes the input into sentences, builds a word-frequency map across the
/// entire text, scores each sentence by the summed frequency of its constituent words (normalized
/// by sentence length), and returns the top-N highest-scoring sentences in their original order.
///
/// All computation is on-device — no network access, no API keys, no data leaves the process.
///
/// ## Usage
/// ```swift
/// let summary = ExtractiveSummarizer.summary(of: longText, maxSentences: 3)
/// ```
///
/// - Note: Separated from `EditorTextView` to honour SR-6 (one responsibility per file)
///   and to make the algorithm testable in isolation. See ISS-137.
public enum ExtractiveSummarizer {

    /// Produces an extractive summary of up to `maxSentences` key sentences.
    ///
    /// - Parameters:
    ///   - text: The full input text to summarize.
    ///   - maxSentences: The maximum number of sentences to include in the summary.
    /// - Returns: A string containing the top-scoring sentences in their original order,
    ///   joined by double newlines. Returns the original text (truncated to 280 characters)
    ///   if there is only one sentence. Returns a fallback message if no summary could be
    ///   generated.
    public static func summary(of text: String, maxSentences: Int) -> String {
        guard !text.isEmpty else {
            return "No text selected."
        }

        // Tokenize into sentences using NaturalLanguage.
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex).map {
            String(text[$0])
        }

        guard sentences.count > 1 else {
            // Single sentence — return it truncated.
            return sentences.first.map { $0.count > 280 ? String($0.prefix(277)) + "…" : $0 }
                ?? text
        }

        // Build term-frequency map (lowercased, non-trivial words).
        var termFreq: [String: Int] = [:]
        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = text
        wordTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            // Skip short words and stop words.
            if word.count > 3 {
                termFreq[word, default: 0] += 1
            }
            return true
        }

        // Score each sentence by summed term frequency (normalized by sentence length).
        struct ScoredSentence {
            let text: String
            let score: Double
        }
        var scored: [ScoredSentence] = []
        for sentence in sentences {
            let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let words = cleaned.split(separator: " ").map(String.init)
            guard words.count >= 4 else { continue }  // Skip very short fragments.
            let totalScore = words.reduce(0.0) { score, word in
                score + Double(termFreq[word.lowercased(), default: 0])
            }
            let normalized = totalScore / Double(max(words.count, 1))
            scored.append(ScoredSentence(text: cleaned, score: normalized))
        }

        // Sort by score descending, take top N, re-sort by original position.
        let top = scored.sorted { $0.score > $1.score }.prefix(maxSentences)
        let result = top.sorted { lhs, rhs in
            guard let lhsIndex = sentences.firstIndex(of: lhs.text),
                let rhsIndex = sentences.firstIndex(of: rhs.text)
            else {
                // If either sentence isn't found, keep stable order by falling back to
                // the other's position (SR-2: no force-unwrap).
                return sentences.firstIndex(of: lhs.text) != nil
            }
            return lhsIndex < rhsIndex
        }
        .map { $0.text }
        .joined(separator: "\n\n")

        return result.isEmpty ? "(Unable to generate summary.)" : result
    }
}
