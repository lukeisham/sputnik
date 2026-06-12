import Foundation
import NaturalLanguage

/// On-device semantic search across open documents using NLEmbedding.
///
/// Chunks each document into sentences, computes an embedding vector for
/// each chunk via `NLEmbedding`, and searches by cosine similarity against
/// the query embedding. Fully on-device — no network, no API key.
///
/// **Performance:** The first call to `NLEmbedding.sentenceEmbedding` loads
/// the ~300 MB model and caches it system-wide. Subsequent calls are fast.
/// Large documents are chunked into sentences (not paragraphs) to keep
/// per-chunk embedding bounds reasonable (SR-3).
///
/// **Threading:** All embedding operations are synchronous inside the
/// `NLEmbedding` API but dispatched on a `Task(priority: .utility)` so
/// they never block the main thread (SR-4).
public enum LocalSemanticSearch {

    /// A single search hit with a relevance score (0–1, higher = more similar).
    public struct Hit: Sendable, Identifiable {
        /// Unique identifier for this hit (document ID + chunk index).
        public let id: String
        /// The document session ID this result belongs to.
        public let documentID: UUID
        /// The matched text chunk.
        public let text: String
        /// Cosine similarity score, 0–1.
        public let score: Float
    }

    /// Search results for a single query.
    public struct Result: Sendable {
        public let query: String
        public let hits: [Hit]
    }

    /// In-memory index entry for a single document chunk.
    private struct IndexEntry: Sendable {
        let documentID: UUID
        let text: String
        let embedding: [Float]
    }

    /// The in-memory search index, rebuilt when documents change.
    @MainActor
    private static var index: [IndexEntry] = []

    /// The query embedding for the current search (cached across many chunks).
    private static var queryEmbedding: [Float] = []

    // MARK: - Public API

    /// Rebuilds the search index from the given documents.
    /// Call this when documents are opened, closed, or their text changes.
    /// Runs embedding computation on a utility background task.
    /// - Parameter documents: Array of `(id: UUID, text: String)` tuples.
    @MainActor
    public static func reindex(documents: [(id: UUID, text: String)]) async {
        let task = Task(priority: .utility) {
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
                return  // NLEmbedding model unavailable (rare on macOS 14+)
            }

            var newIndex: [IndexEntry] = []
            let tokenizer = NLTokenizer(unit: .sentence)
            let dimension = embedding.dimension

            for (docID, text) in documents {
                tokenizer.string = text
                let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex)
                    .map { String(text[$0]) }
                    .filter { $0.split(separator: " ").count >= 4 }  // Skip fragments.

                for sentence in sentences {
                    guard let vector = embedding.vector(for: sentence) else { continue }
                    // NLEmbedding.vector returns UnsafePointer<Float>? — copy into an array.
                    var arr = [Float](repeating: 0, count: dimension)
                    for i in 0..<dimension {
                        arr[i] = Float(vector[i])
                    }
                    newIndex.append(
                        IndexEntry(documentID: docID, text: sentence, embedding: arr))
                }
            }

            await MainActor.run {
                index = newIndex
            }
        }
        _ = await task.value
    }

    /// Searches the current index for documents semantically similar to the query.
    /// Returns ranked results with cosine similarity scores.
    /// - Parameters:
    ///   - query: The natural-language search query.
    ///   - maxResults: Maximum number of hits to return. Default 10.
    /// - Returns: A `Result` with sorted hits (highest score first).
    @MainActor
    public static func search(query: String, maxResults: Int = 10) async -> Result {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Result(query: query, hits: [])
        }

        // Capture the current index on the main actor before dispatching to utility QoS.
        let snapshot = index

        let task = Task(priority: .utility) {
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
                let queryVector = embedding.vector(for: query)
            else {
                return Result(query: query, hits: [])
            }

            let dimension = embedding.dimension
            // Copy query vector into an array.
            var qArr = [Float](repeating: 0, count: dimension)
            for i in 0..<dimension { qArr[i] = Float(queryVector[i]) }

            // Score every indexed chunk by cosine similarity.
            var scored: [(IndexEntry, Float)] = []
            for entry in snapshot {
                let sim = cosineSimilarity(qArr, entry.embedding)
                scored.append((entry, sim))
            }

            // Sort by score descending, take top N.
            let top = scored.sorted { $0.1 > $1.1 }.prefix(maxResults)
            let hits = top.map { entry, score in
                Hit(
                    id: "\(entry.documentID.uuidString)-\(entry.text.prefix(20))",
                    documentID: entry.documentID,
                    text: entry.text,
                    score: score
                )
            }
            return Result(query: query, hits: hits)
        }
        return await task.value
    }

    // MARK: - Helpers

    /// Computes cosine similarity between two vectors of equal dimension.
    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let magnitude = sqrt(normA) * sqrt(normB)
        return magnitude > 0 ? dotProduct / magnitude : 0
    }
}
