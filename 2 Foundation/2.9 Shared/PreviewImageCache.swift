import AppKit
import Foundation

/// A thread-safe image cache for preview panels (Markdown, HTML, PDF).
///
/// Wraps `NSCache<NSURL, NSImage>` and adds generation-based invalidation.
/// All images are automatically downsampled to fit within `maxDimension` to reduce
/// peak memory usage (SR-3 — low RAM).
///
/// Usage:
/// ```swift
/// let image = await PreviewImageCache.shared.image(for: url) { [weak self] in
///     // Load and return NSImage if cache miss
///     NSImage(contentsOf: url)
/// }
/// ```
// Actor isolation provides Sendable safety automatically; @unchecked is not needed.
// NSImage is not Sendable, but it is actor-isolated here so the conformance is automatic.
public actor PreviewImageCache {

    /// Shared singleton cache.
    public static let shared = PreviewImageCache()

    /// Maximum dimension (width or height) for cached images. Default 2048px.
    /// Images larger than this are downsampled during caching.
    public var maxDimension: CGFloat = 2048 {
        didSet {
            // Invalidate cache on size-limit change so old oversized images are dropped
            invalidate()
        }
    }

    // MARK: - Private state

    private let cache = NSCache<NSURL, NSImage>()
    private var generation: UInt64 = 0

    // MARK: - Public API

    /// Retrieves or loads an image from the cache.
    ///
    /// If the image is already cached, returns it immediately. If not, calls
    /// `loader()` on a background task, downsamples if needed, caches, and returns.
    ///
    /// - Parameters:
    ///   - url: Cache key (the image's source URL).
    ///   - loader: Closure that loads and returns the raw `NSImage` on cache miss.
    ///   - Returns: Downsampled image, or `nil` if `loader()` returned `nil`.
    public func image(
        for url: URL,
        loader: @Sendable @escaping () -> NSImage?
    ) async -> NSImage? {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        // Cache miss — load on background
        let loaded = await Task.detached(priority: .utility) {
            loader()
        }.value

        guard let image = loaded else { return nil }

        // Downsample if needed
        let downsampled = downsample(image, maxDimension: maxDimension)
        cache.setObject(downsampled, forKey: url as NSURL)

        return downsampled
    }

    /// Stores an image in the cache (for cases where the image
    /// is already decoded).
    ///
    /// - Parameters:
    ///   - image: The image to cache.
    ///   - url: The cache key.
    public func set(_ image: NSImage, for url: URL) {
        let downsampled = downsample(image, maxDimension: 2048)
        cache.setObject(downsampled, forKey: url as NSURL)
    }

    /// Invalidates the entire cache (e.g., on document switch or size-limit change).
    public func invalidate() {
        generation &+= 1
        cache.removeAllObjects()
    }

    /// Invalidates a single cached image (e.g., if the source file is updated).
    public func invalidate(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    // MARK: - Private helpers

    /// Downsamples an image to fit within `maxDimension` while preserving aspect ratio.
    private nonisolated func downsample(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let maxDim = max(size.width, size.height)

        // Image already fits — return as-is
        guard maxDim > maxDimension else { return image }

        // Scale to fit
        let scale = maxDimension / maxDim
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let downsampled = NSImage(size: newSize)
        downsampled.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0)
        downsampled.unlockFocus()

        return downsampled
    }
}
