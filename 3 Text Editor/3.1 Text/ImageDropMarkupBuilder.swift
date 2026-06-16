import AppKit

/// Stateless helpers for constructing image-drop markup and inspecting pasteboards.
///
/// Extracted from `EditorTextView` to honour SR-6 (one responsibility per file).
/// The three `NSDraggingDestination` overrides remain in `EditorTextView` because they
/// are AppKit override methods; they delegate here for URL extraction and markup building.
///
/// - Note: All methods are pure functions — no state, no side effects beyond reading the pasteboard.
public enum ImageDropMarkupBuilder {

    /// Checks if the pasteboard contains an image file URL.
    /// - Parameter pasteboard: The pasteboard to inspect.
    /// - Returns: `true` if at least one image file URL is found.
    public static func hasImageFileURL(in pasteboard: NSPasteboard) -> Bool {
        imageFileURL(from: pasteboard) != nil
    }

    /// Extracts the first image file URL from the pasteboard, if any.
    /// - Parameter pasteboard: The pasteboard to inspect.
    /// - Returns: A file URL for the first image found, or `nil`.
    public static func imageFileURL(from pasteboard: NSPasteboard) -> URL? {
        guard let items = pasteboard.pasteboardItems else { return nil }
        for item in items {
            guard let urlString = item.string(forType: .fileURL),
                let url = URL(string: urlString)
            else { continue }
            // Normalise the file URL.
            let fileURL = if url.isFileURL { url } else { URL(fileURLWithPath: url.path) }
            guard fileURL.isFileURL else { continue }
            let ext = fileURL.pathExtension.lowercased()
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "bmp", "tiff"]
            if imageExtensions.contains(ext) {
                return fileURL
            }
        }
        return nil
    }

    /// Computes the markup string to insert for the given image file URL.
    ///
    /// Uses Markdown syntax `![filename](path)` for `.markdown` mode and
    /// HTML `<img src="path" alt="filename">` for `.html` mode.
    /// Falls back to Markdown for all other modes.
    /// - Parameters:
    ///   - imageURL: The URL of the dropped image file.
    ///   - mode: The active editor mode (determines Markdown vs HTML syntax).
    ///   - editorFileURL: The URL of the currently open editor file, used to compute
    ///     a relative path. Pass `nil` to use the absolute path.
    /// - Returns: A Markdown or HTML markup string.
    public static func markupString(for imageURL: URL, mode: EditorMode, editorFileURL: URL?)
        -> String
    {
        let useHTML = mode == .html
        let filename = imageURL.deletingPathExtension().lastPathComponent
        let path = relativePath(for: imageURL, editorFileURL: editorFileURL)

        if useHTML {
            let escapedPath =
                path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
            let escapedAlt =
                filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
            return "<img src=\"\(escapedPath)\" alt=\"\(escapedAlt)\">"
        } else {
            // Markdown syntax (default fallback)
            return "![\(filename)](\(path))"
        }
    }

    /// Computes a relative path from the editor's current file directory to `imageURL`.
    /// Falls back to the absolute path when no editor file is open.
    /// - Parameters:
    ///   - imageURL: The URL of the dropped image file.
    ///   - editorFileURL: The URL of the currently open editor file, or `nil`.
    /// - Returns: A relative or absolute path string.
    public static func relativePath(for imageURL: URL, editorFileURL: URL?) -> String {
        guard let editorFileURL else {
            return imageURL.path
        }
        let editorDir = editorFileURL.deletingLastPathComponent()
        let imagePath = imageURL.resolvingSymlinksInPath().path
        let dirPath = editorDir.resolvingSymlinksInPath().path

        guard imagePath.hasPrefix(dirPath) else {
            // Image is outside the editor's directory tree — use absolute path.
            return imageURL.path
        }

        var relative = String(imagePath.dropFirst(dirPath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return relative.isEmpty ? imageURL.lastPathComponent : relative
    }
}
