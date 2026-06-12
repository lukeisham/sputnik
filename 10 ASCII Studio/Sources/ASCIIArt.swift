import Foundation

/// A typed model carrying ASCII art content, source metadata, and conversion settings.
///
/// `Sendable` by value — safe to pass across concurrency boundaries.
public struct ASCIIArt: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var asciiContent: String
    public var sourceImageURL: URL?
    public var style: ImageToASCIIConverter.RampStyle
    public var width: Int
    public var createdAt: Date
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        asciiContent: String,
        sourceImageURL: URL? = nil,
        style: ImageToASCIIConverter.RampStyle = .block,
        width: Int = 80,
        createdAt: Date = Date(),
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.asciiContent = asciiContent
        self.sourceImageURL = sourceImageURL
        self.style = style
        self.width = width
        self.createdAt = createdAt
        self.tags = tags
    }
}
