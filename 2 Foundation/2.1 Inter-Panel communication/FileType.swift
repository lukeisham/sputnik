import Foundation

/// Classifies a file by its extension so routing and display logic can branch without
/// inspecting raw strings outside this type.
public enum FileType: String, Codable, Sendable, Hashable {
    case text
    case markdown
    case html
    case pdf
    case ascii
    case binary
    case unknown
}

public extension FileType {
    /// Derives the `FileType` from the file extension of `url`.
    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "txt":           self = .text
        case "md", "markdown": self = .markdown
        case "html", "htm":   self = .html
        case "pdf":           self = .pdf
        case "asc", "ascii":  self = .ascii
        case "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp",
             "zip", "tar", "gz", "bz2", "xz", "7z",
             "exe", "dmg", "pkg", "o", "a", "dylib":
            self = .binary
        default:              self = .unknown
        }
    }
}
