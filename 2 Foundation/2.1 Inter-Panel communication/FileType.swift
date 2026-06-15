import Foundation

/// Classifies a file by its extension so routing and display logic can branch without
/// inspecting raw strings outside this type.
public enum FileType: String, Codable, Sendable, Hashable {
    case text
    case markdown
    case html
    case pdf
    case ascii
    case json
    case image
    case binary
    case unknown
}

extension FileType {
    /// The canonical file extension for this type (used when saving as a template).
    public var defaultExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        case .ascii: return "ascii"
        case .json: return "json"
        case .pdf, .image, .binary, .unknown: return "txt"
        }
    }

    /// Derives the `FileType` from a bare extension string (e.g. `"md"`, `"html"`).
    public init(extension ext: String) {
        self.init(url: URL(fileURLWithPath: "f.\(ext)"))
    }

    /// Derives the `FileType` from the file extension of `url`.
    public init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "txt": self = .text
        case "md", "markdown": self = .markdown
        case "html", "htm": self = .html
        case "pdf": self = .pdf
        case "asc", "ascii": self = .ascii
        case "json": self = .json
        case "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp": self = .image
        case "zip", "tar", "gz", "bz2", "xz", "7z",
            "exe", "dmg", "pkg", "o", "a", "dylib":
            self = .binary
        default: self = .unknown
        }
    }
}
