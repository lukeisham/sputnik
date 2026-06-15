import Foundation

/// A single template file on disk, represented as an immutable value.
///
/// `id` is the file URL so equality checks and `ForEach` identity are
/// grounded in the real filesystem path — no separate UUID needed.
public struct TemplateRecord: Identifiable, Hashable, Sendable {

    /// The file URL of the template; also used as the stable identity.
    public let id: URL

    /// Display name derived from the filename without extension.
    public let name: String

    /// File extension (e.g. `"md"`, `"html"`), lower-cased.
    public let fileExtension: String

    /// Derives `name` and `fileExtension` from `url`.
    public init(url: URL) {
        self.id = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
    }
}
