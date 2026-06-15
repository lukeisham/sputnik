import Foundation

/// A single outbound Google search link shown in the "More details:" section of a help topic.
public struct HelpExternalSearch: Sendable, Equatable {
    public let label: String
    public let url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }
}
