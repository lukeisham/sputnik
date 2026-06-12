import AppKit
import Foundation
import FoundationModule
import SputnikShared
import Observation
import ResourcesModule

/// The view model for the Markdown Preview panel.
///
/// Owns the rendered output, observes the active Markdown document, and orchestrates
/// the parse pipeline. All published state is `@MainActor`-isolated; the heavy
/// `AttributedString(markdown:)` call runs on a background `Task(priority: .utility)`
/// and the result is published back on the main actor (MR-3, SW-1, SR-4).
///
/// A stale-render guard (generation counter) ensures that if a newer `render` call
/// arrives before the previous one completes, the older result is discarded.
///
/// Block-level caching (ISS-064): Markdown is split on blank lines into blocks.
/// Text-only blocks are cached by hash; only changed blocks are re-rendered, giving
/// O(delta_blocks) parse time instead of O(whole_document) on every keystroke.
///
/// Image handling: local `![alt](path)` references are resolved via `PreviewImageResolver`
/// (module 9) and inserted as `NSTextAttachment`s. Remote `http(s)` references render as
/// a labelled placeholder — no network fetch occurs in the preview.
@Observable
@MainActor
public final class MarkdownPreviewViewModel {

    // MARK: - Owned state

    /// The latest successfully rendered Markdown output. Empty by default.
    public var renderedString: NSAttributedString = NSAttributedString()

    /// Preserved vertical scroll position across re-renders.
    public var scrollOffset: CGFloat = 0

    /// User-adjustable zoom factor. Range 0.5 … 2.0; default 1.0.
    public var fontScale: CGFloat = 1.0 {
        didSet {
            fontScale = min(2.0, max(0.5, fontScale))
        }
    }

    /// `true` while a background parse is in flight.
    public var isRendering: Bool = false

    /// Non-nil when `AttributedString(markdown:)` threw. Surfaced as a subtle banner.
    public var renderError: String? = nil

    /// `true` when the active document exceeds the large-file threshold (ISS-064, Step 10).
    /// The panel shows a visual indicator and skips scroll sync in degraded mode.
    public var isLargeFile: Bool = false

    /// Source map from the last completed render. Maps rendered character ranges to
    /// source line ranges for ⌘-click-to-source navigation (ISS-065, Step 8).
    public var sourceMap: [MarkdownSourceBlock] = []

    // MARK: - Constants

    /// Character count above which large-file degraded mode activates.
    private static let largeFileThreshold = 80_000

    // MARK: - Stale-render guard

    /// Monotonically increasing counter. Each `render` call increments it; the
    /// background task captures the current value and discards its result if the
    /// counter has advanced further by the time it completes.
    private var renderGeneration: UInt64 = 0

    /// Throttles rapid re-render requests during fast typing (SR-4).
    /// Delay is adaptive — shorter for small docs, longer for large (Step 1).
    private let renderThrottle = RenderThrottle()

    /// Per-block render cache keyed by block text hash.
    /// Text-only blocks are cached synchronously; image blocks always re-render.
    private var blockCache: [Int: SendableAttributedString] = [:]

    // MARK: - AppState observation

    /// Weak reference to the shared `AppState`, set by the panel on appear.
    /// Held weakly because `AppState` is owned by the app root (SW-2).
    private weak var appState: AppState?

    // MARK: - Public API

    /// Creates a new, empty view model.
    public init() {}

    /// Wires the view model to the shared `AppState`. Called once from
    /// `MarkdownPreviewPanel` when the panel first appears.
    ///
    /// - Parameter appState: The app's shared state. Held weakly.
    public func configure(appState: AppState) {
        self.appState = appState
    }

    /// Renders raw Markdown text into a styled `NSAttributedString` using block-level
    /// caching. Only blocks whose text changed since the last render are re-parsed.
    ///
    /// Runs the heavy parse work on a background `Task(priority: .utility)`. On completion,
    /// `renderedString` is published on `@MainActor`. If a newer `render` call arrives before
    /// this one completes, the stale result is discarded (generation guard).
    ///
    /// - Parameters:
    ///   - markdown: The raw Markdown source text.
    ///   - baseDir:  The directory used to resolve relative image paths. `nil` disables
    ///               local image loading (images render as placeholder labels).
    public func render(markdown: String, baseDir: URL? = nil) {
        renderGeneration &+= 1
        let generation = renderGeneration

        isRendering = true
        renderError = nil
        isLargeFile = markdown.utf16.count >= Self.largeFileThreshold
        renderThrottle.delay = adaptiveDelay(for: markdown)

        // Snapshot the block cache on the main actor before entering the background task.
        let cacheSnapshot = blockCache

        renderThrottle.throttle { [weak self, generation, cacheSnapshot] in
            let (nsResult, newSourceMap, newEntries) = await buildBlockCachedAttributedString(
                markdown: markdown, baseDir: baseDir, cache: cacheSnapshot)
            let wrapped = SendableAttributedString(value: nsResult)
            await self?.applyRenderedResult(
                wrapped.value,
                sourceMap: newSourceMap,
                newCacheEntries: newEntries,
                generation: generation)
        }
    }

    /// Backward-compatible forwarder: renders Markdown without a base directory.
    public func render(markdown: String) {
        render(markdown: markdown, baseDir: nil)
    }

    /// Backward-compatible forwarder: renders Markdown at the given font scale.
    /// The scale is applied downstream in `MarkdownRenderView`; this method shares
    /// the parse path with `render(markdown:baseDir:)`.
    public func render(markdown: String, fontScale: CGFloat) {
        render(markdown: markdown, baseDir: nil)
    }

    // MARK: - Private helpers

    /// Returns a debounce delay scaled to the document size.
    /// Small files render immediately; large files coalesce more aggressively (Step 1).
    private func adaptiveDelay(for text: String) -> TimeInterval {
        switch text.utf16.count {
        case ..<2_000:           return 0.05
        case 2_000..<20_000:     return 0.10
        case 20_000..<80_000:    return 0.20
        default:                 return 0.30
        }
    }

    /// Applies a successfully rendered result to `@MainActor` state, guarding against
    /// stale renders from superseded generations.
    @MainActor
    private func applyRenderedResult(
        _ string: NSAttributedString,
        sourceMap: [MarkdownSourceBlock],
        newCacheEntries: [Int: SendableAttributedString],
        generation: UInt64
    ) {
        guard generation == renderGeneration else { return }
        isRendering = false
        renderError = nil
        renderedString = string
        self.sourceMap = sourceMap
        // Merge new entries; evict the whole cache when it grows too large.
        for (key, value) in newCacheEntries {
            blockCache[key] = value
        }
        if blockCache.count > 500 {
            blockCache.removeAll()
        }
    }
}
