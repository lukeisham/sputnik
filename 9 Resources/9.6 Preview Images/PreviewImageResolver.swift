import AppKit
import Foundation
import ImageIO

/// Resolves image references (local file paths) and provides downsampled data/NSImage objects
/// bounded by a 20 MB byte cap and 2000 px pixel cap. All heavy I/O runs on a background queue.
/// Path safety: rejects absolute paths and `..` escapes.
public actor PreviewImageResolver {

    // MARK: - Limits (single source of truth for SR-1)

    private static let maxByteSize: Int64 = 20 * 1024 * 1024  // 20 MB
    private static let maxPixelDimension: Int = 2000  // max per side

    // MARK: - Result type

    /// Outcome of resolving an image reference.
    public enum ResolvedImage: Sendable {
        /// Decoded and downsampled to pixels bounded by the limit; MIME type included.
        case image(data: Data, mime: String, pixelSize: CGSize)
        /// File exceeds byte cap — not read into memory.
        case tooLarge(name: String, byteCount: Int64)
        /// File format not supported or cannot be decoded.
        case unsupported
        /// File does not exist or path escape detected.
        case notFound
    }

    // MARK: - Init

    public init() {}

    // MARK: - Main API

    /// Resolves a reference against a base directory; returns the resolution result.
    ///
    /// Path safety: `reference` is interpreted relative to `baseDir`. Absolute paths and
    /// any paths containing `..` are rejected (returns `.notFound`). If the resolved path
    /// escapes `baseDir`, also returns `.notFound`.
    ///
    /// - Parameters:
    ///   - reference: A file path (relative, or a URL with `http(s):/data:` schemes are
    ///     left unhandled — caller passes these through).
    ///   - baseDir: The directory to resolve `reference` against.
    /// - Returns: A `ResolvedImage` describing the outcome.
    public func resolve(reference: String, relativeTo baseDir: URL) -> ResolvedImage {
        // Ignore non-local references
        if reference.hasPrefix("http://") || reference.hasPrefix("https://") || reference.hasPrefix("data:") {
            return .notFound
        }

        // Reject absolute paths and `..` escapes
        if reference.hasPrefix("/") || reference.contains("..") {
            return .notFound
        }

        let fileURL = baseDir.appendingPathComponent(reference, isDirectory: false)
        let standardized = fileURL.standardizedFileURL
        let baseStandardized = baseDir.standardizedFileURL

        // Ensure the resolved path does not escape baseDir
        guard standardized.path.hasPrefix(baseStandardized.path) else {
            return .notFound
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return .notFound
        }

        // Check file size before reading
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: standardized.path)
            if let fileSize = attrs[.size] as? Int64, fileSize > Self.maxByteSize {
                return .tooLarge(name: standardized.lastPathComponent, byteCount: fileSize)
            }
        } catch {
            return .notFound
        }

        // Decode and downsample
        return decodeImage(at: standardized)
    }

    /// Convenience: resolves the reference and returns an `NSImage` on success, or `nil`
    /// on failure (unsupported, too large, not found, etc.).
    public func nsImage(reference: String, relativeTo baseDir: URL) -> NSImage? {
        let resolved = resolve(reference: reference, relativeTo: baseDir)
        if case .image(let data, _, _) = resolved {
            return NSImage(data: data)
        }
        return nil
    }

    /// Convenience: resolves the reference and returns `(data, mime)` on success, or `nil` on failure.
    public func data(reference: String, relativeTo baseDir: URL) -> (data: Data, mime: String)? {
        let resolved = resolve(reference: reference, relativeTo: baseDir)
        if case .image(let data, let mime, _) = resolved {
            return (data, mime)
        }
        return nil
    }

    // MARK: - Private: Image decoding and downsampling

    /// Decodes an image file using ImageIO, downsamples via thumbnail generation,
    /// and returns the result as a TIFF or JPEG.
    private func decodeImage(at url: URL) -> ResolvedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .unsupported
        }

        let options: [NSString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .unsupported
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let nsImage = NSImage()
        nsImage.addRepresentation(bitmap)

        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Encode to TIFF (loss-free and fast)
        guard let tiffData = bitmap.representation(using: .tiff, properties: [:]) else {
            return .unsupported
        }

        return .image(data: tiffData, mime: "image/tiff", pixelSize: pixelSize)
    }
}
