import AppKit
import Foundation
import Observation
import ResourcesModule

/// @unchecked Sendable box for crossing actor boundaries with NSAttributedString.
/// NSAttributedString is immutable after creation, making the transfer safe.
private struct SendableAttributedString: @unchecked Sendable {
    let value: NSAttributedString
}

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

    // MARK: - Stale-render guard

    /// Monotonically increasing counter. Each `render` call increments it; the
    /// background task captures the current value and discards its result if the
    /// counter has advanced further by the time it completes.
    private var renderGeneration: UInt64 = 0

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

    /// Renders raw Markdown text into a styled `NSAttributedString`, resolving
    /// local image references (e.g. `![alt](path)`) against `baseDir`.
    ///
    /// Runs on a background `Task(priority: .utility)`. On completion,
    /// `renderedString` is published on `@MainActor`. If a newer `render` call
    /// arrives before this one completes, the stale result is discarded.
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

        Task.detached(priority: .utility) { [weak self, generation] in
            let nsResult = await buildNSAttributedString(markdown: markdown, baseDir: baseDir)
            let wrapped = SendableAttributedString(value: nsResult)
            await self?.applyRenderedResult(wrapped.value, generation: generation)
        }
    }

    /// Backward-compatible forwarder: renders Markdown without a base directory.
    ///
    /// - Parameter markdown: The raw Markdown source text.
    public func render(markdown: String) {
        render(markdown: markdown, baseDir: nil)
    }

    /// Backward-compatible forwarder: renders Markdown at the given font scale.
    ///
    /// The scale is **not** baked into the parsed `NSAttributedString` — it is applied
    /// downstream in `MarkdownRenderView` via `NSTextView.font`. This method therefore
    /// shares the parse path with `render(markdown:baseDir:)`.
    ///
    /// - Parameters:
    ///   - markdown:  The raw Markdown source text.
    ///   - fontScale: The zoom factor; applied by the render view, not here.
    public func render(markdown: String, fontScale: CGFloat) {
        render(markdown: markdown, baseDir: nil)
    }

    // MARK: - Private helpers

    /// Applies a successfully rendered result to `@MainActor` state, guarding against
    /// stale renders from superseded generations.
    @MainActor
    private func applyRenderedResult(_ string: NSAttributedString, generation: UInt64) {
        guard generation == renderGeneration else { return }
        isRendering = false
        renderError = nil
        renderedString = string
    }
}

// MARK: - File-scope async helpers (nonisolated; called from Task.detached)

/// Builds a styled `NSAttributedString` from Markdown source, inserting
/// `NSTextAttachment`s for local image references and placeholder labels for
/// remote references. Text segments are rendered via `AttributedString(markdown:)`.
private func buildNSAttributedString(markdown: String, baseDir: URL?) async -> NSAttributedString {
    // Regex matches: ![alt text](path/or/url)
    let imagePattern = /!\[([^\]]*)\]\(([^)\s]+)\)/

    let allMatches = markdown.matches(of: imagePattern)

    // Fast path — no images: skip segment splitting overhead.
    if allMatches.isEmpty {
        return parseMarkdownSegment(markdown)
    }

    let resolver = PreviewImageResolver()
    let result = NSMutableAttributedString()
    var lastEnd = markdown.startIndex

    for match in allMatches {
        // Render text segment before this image reference.
        let textPart = String(markdown[lastEnd..<match.range.lowerBound])
        if !textPart.isEmpty {
            result.append(parseMarkdownSegment(textPart))
        }

        let alt  = String(match.output.1)
        let path = String(match.output.2)
        result.append(await resolveImageAttachment(path: path, alt: alt,
                                                   baseDir: baseDir, resolver: resolver))
        lastEnd = match.range.upperBound
    }

    // Render any text after the last image.
    let tail = String(markdown[lastEnd...])
    if !tail.isEmpty {
        result.append(parseMarkdownSegment(tail))
    }

    return result
}

/// Renders a Markdown text segment (no images) to an `NSAttributedString`.
/// Falls back to plain text if the parser throws.
private func parseMarkdownSegment(_ text: String) -> NSAttributedString {
    do {
        let attributed = try AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )
        return NSAttributedString(attributed)
    } catch {
        return NSAttributedString(string: text)
    }
}

/// Returns the `NSAttributedString` fragment for a single image reference.
///
/// - Remote (`http`/`https`): labelled text placeholder — no network fetch.
/// - Local, resolved `.image`: `NSTextAttachment` containing the downsampled `NSImage`.
/// - Local, `.tooLarge`: labelled size-cap placeholder.
/// - Local, `.notFound`/`.unsupported` or no `baseDir`: labelled alt-text placeholder.
private func resolveImageAttachment(
    path: String, alt: String, baseDir: URL?, resolver: PreviewImageResolver
) async -> NSAttributedString {
    // Remote reference — show a labelled placeholder, never fetch.
    if path.hasPrefix("http://") || path.hasPrefix("https://") {
        let label = alt.isEmpty ? "image" : alt
        return NSAttributedString(string: "[\(label)]")
    }

    guard let dir = baseDir else {
        let label = alt.isEmpty ? path : alt
        return NSAttributedString(string: "[\(label)]")
    }

    let resolved = await resolver.resolve(reference: path, relativeTo: dir)
    switch resolved {
    case .image(let data, _, _):
        if let img = NSImage(data: data) {
            let attachment = NSTextAttachment()
            attachment.image = img
            let str = NSMutableAttributedString(attachment: attachment)
            str.append(NSAttributedString(string: "\n"))
            return str
        }
        // Image data failed to decode — fall through to placeholder.
        let label = alt.isEmpty ? path : alt
        return NSAttributedString(string: "[\(label)]")

    case .tooLarge(let name, _):
        return NSAttributedString(string: "[Image too large: \(name)]")

    case .notFound, .unsupported:
        let label = alt.isEmpty ? path : alt
        return NSAttributedString(string: "[\(label)]")
    }
}
