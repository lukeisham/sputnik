import Foundation

/// A single ASCII art piece in the library.
///
/// Value type — copied by callers, never mutated after index load.
public struct ASCIIArtRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let tags: [String]
    public let category: String
    /// Relative path under `9 Resources/9.1 ASCIILibrary/` (e.g. `"Arrows/simple_right.txt"`).
    public let filename: String

    public init(id: String, title: String, tags: [String], category: String, filename: String) {
        self.id = id
        self.title = title
        self.tags = tags
        self.category = category
        self.filename = filename
    }
}
