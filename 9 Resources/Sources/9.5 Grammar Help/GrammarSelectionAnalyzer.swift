import Foundation
import NaturalLanguage

/// Analyzes a selected span of text to determine its word count and approximate grammatical role.
///
/// Uses NaturalLanguage `NLTagger` with `.lexicalClass` (parts of speech) to find the sentence's
/// main verb, then approximates whether the selection is a subject (noun phrase before main verb)
/// or object (noun phrase after main verb). This is a heuristic — passive voice, object-fronting,
/// and inversions will misclassify. See `SelectionRole` comments.
///
/// The analyzer runs off-main-thread. It is `Sendable` and safe to use from `@MainActor`.
///
/// Usage:
/// ```swift
/// let analysis = await GrammarSelectionAnalyzer.analyze(
///     fullText: "The cat sat on the mat",
///     cursorOffset: 4,
///     selectionLength: 3   // "cat"
/// )
/// print(analysis.wordCount)  // 1
/// print(analysis.role)       // .subject
/// ```
public actor GrammarSelectionAnalyzer {

    // MARK: - Public Types

    /// The approximate grammatical role of a selected span.
    ///
    /// **Limitations:** This classification is heuristic and based on position relative to the
    /// main verb. It will misclassify in passive voice, with fronted objects, and in complex
    /// sentence structures. Always treat as an approximation, not a definitive parse.
    public enum SelectionRole: Sendable, Equatable {
        /// The selection appears to be a subject (noun phrase before main verb).
        case subject
        /// The selection appears to be an object (noun phrase after main verb).
        case object
        /// Could not determine a role (selection spans verb, ambiguous, or no verb found).
        case unknown
    }

    /// The result of analyzing a selection.
    public struct AnalysisResult: Sendable, Equatable {
        /// The number of distinct words in the selection (space-separated).
        public let wordCount: Int
        /// The approximate grammatical role of the selection.
        public let role: SelectionRole
    }

    // MARK: - Analysis

    /// Analyzes the given selection span to determine word count and grammatical role.
    ///
    /// - Parameters:
    ///   - fullText: The complete text (e.g. the document body).
    ///   - cursorOffset: The UTF-16 offset where the selection starts.
    ///   - selectionLength: The length of the selection in UTF-16 code units.
    /// - Returns: An `AnalysisResult` with the word count and role classification.
    public static func analyze(
        fullText: String,
        cursorOffset: Int,
        selectionLength: Int
    ) async -> AnalysisResult {
        // Count words in the selection
        let selectedRange = NSRange(location: cursorOffset, length: selectionLength)
        let selectedText = (fullText as NSString).substring(with: selectedRange)
        let wordCount = selectedText.split(separator: " ").count

        // Approximative role classification via POS tagging
        let role = await determineRole(
            fullText: fullText,
            selectedRange: selectedRange,
            wordCount: wordCount
        )

        return AnalysisResult(wordCount: wordCount, role: role)
    }

    // MARK: - Private

    /// Determines the grammatical role by tagging the full text for parts of speech.
    private static func determineRole(
        fullText: String,
        selectedRange: NSRange,
        wordCount: Int
    ) async -> SelectionRole {
        // Off-main-thread tagging using NaturalLanguage
        let result = await Task.detached { () -> SelectionRole in
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = fullText

            // Find the main verb (VERB tag) closest to the selection
            var mainVerbLocation: Int? = nil
            let fullRange = fullText.startIndex..<fullText.endIndex

            tagger.enumerateTags(in: fullRange, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
                if tag == .verb {
                    // Convert String.Index range to UTF-16 offset
                    let location = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
                    mainVerbLocation = location
                }
                return true  // Continue enumeration
            }

            guard let mainVerbLocation else {
                return .unknown
            }

            let selectionEnd = selectedRange.location + selectedRange.length
            if selectedRange.location < mainVerbLocation && selectionEnd <= mainVerbLocation {
                return .subject
            } else if selectedRange.location >= mainVerbLocation {
                return .object
            } else {
                return .unknown
            }
        }.value

        return result
    }
}
