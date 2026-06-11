import AppKit
import Foundation
import FoundationModule
import Observation
import ResourcesModule

// MARK: - PresentationIntent styling

/// Font sizes (in points) for Markdown heading levels (1…6).
private let headingFontSizes: [CGFloat] = [28, 22, 18, 16, 14, 13]

/// A lightweight Swift-side snapshot of a `PresentationIntent` kind and its
/// character range. Collected from `AttributedString.runs` before bridging to
/// `NSAttributedString`, so we avoid referencing the Objective-C `NSPresentationIntent`
/// type entirely.
private enum ParsedIntentKind: Equatable {
    case header(level: Int)
    case codeBlock
    case blockQuote
    case unorderedList
    case orderedList
    case listItem
    case table
    case tableCell
}

/// Applies visual attributes to an `NSAttributedString` based on `PresentationIntent`
/// metadata emitted by `AttributedString(markdown:options:)` with `.full` parsing.
///
/// `NSTextView` does **not** automatically render `PresentationIntent` attributes —
/// headings appear as plain text, code blocks have no background, etc. This function
/// extracts intent information from the Swift `AttributedString` runs (before bridging)
/// and maps it to standard `NSAttributedString` visual attributes (font, color,
/// paragraph style) that `NSTextView` renders natively.
///
/// - Parameter attributed: The parsed `AttributedString` (Swift type) containing
///   `PresentationIntent` information in its runs.
/// - Returns: An `NSAttributedString` with visual styling applied.
private func applyPresentationIntentStyling(_ attributed: AttributedString) -> NSAttributedString {
    // 1. Collect intent kinds and their ranges from the Swift AttributedString runs.
    var intents: [(NSRange, ParsedIntentKind)] = []

    for run in attributed.runs {
        guard let intent = run.presentationIntent else { continue }
        guard let kind = parseIntentKind(intent) else { continue }
        let nsRange = NSRange(run.range, in: attributed)
        intents.append((nsRange, kind))
    }

    // 2. Bridge to NSMutableAttributedString and apply visual attributes.
    let result = NSMutableAttributedString(attributed)
    for (range, kind) in intents {
        applyKindAttributes(kind, to: result, range: range)
    }

    return result
}

/// Extracts a `ParsedIntentKind` from a Swift `AttributedString.PresentationIntent`.
private func parseIntentKind(
    _ intent: AttributedString.PresentationIntent
) -> ParsedIntentKind? {
    switch intent.kind {
    case .header(let level):
        return .header(level: level)
    case .codeBlock:
        return .codeBlock
    case .blockQuote:
        return .blockQuote
    case .unorderedList:
        return .unorderedList
    case .orderedList:
        return .orderedList
    case .listItem:
        return .listItem
    case .table:
        return .table
    case .tableCell:
        return .tableCell
    default:
        return nil
    }
}

/// Maps a `ParsedIntentKind` to visual `NSAttributedString` attributes and applies
/// them to the given range.
private func applyKindAttributes(
    _ kind: ParsedIntentKind,
    to string: NSMutableAttributedString,
    range: NSRange
) {
    switch kind {
    case .header(let level):
        let idx = max(0, min(level - 1, headingFontSizes.count - 1))
        let fontSize = headingFontSizes[Int(idx)]
        string.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: range)

    case .codeBlock:
        string.addAttribute(
            .font,
            value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            range: range
        )
        string.addAttribute(
            .backgroundColor,
            value: NSColor.systemGray.withAlphaComponent(0.12),
            range: range
        )

    case .blockQuote:
        string.addAttribute(.foregroundColor, value: NSColor.systemGray, range: range)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 20
        paragraphStyle.firstLineHeadIndent = 20
        paragraphStyle.tailIndent = -8
        string.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

    case .unorderedList, .orderedList:
        // List container — no direct visual styling; child `.listItem` ranges carry
        // the actual list content.
        break

    case .listItem:
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.headIndent = 16
        string.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

    case .table, .tableCell:
        // Tables in AttributedString(markdown:) produce structured cells but without
        // grid/border attributes. A full table layout (NSTableView overlay) is complex;
        // for now, leave table cells styled as plain inline text so content is legible.
        break
    }
}

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

    /// Throttles rapid re-render requests during fast typing (SR-4).
    private let renderThrottle = RenderThrottle()

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

        renderThrottle.throttle { [weak self, generation] in
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

        let alt = String(match.output.1)
        let path = String(match.output.2)
        result.append(
            await resolveImageAttachment(
                path: path, alt: alt,
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
        var attributed = try AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full
            )
        )
        return applyPresentationIntentStyling(attributed)
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
        let fileURL = dir.appendingPathComponent(path)
        let img = await PreviewImageCache.shared.image(for: fileURL) {
            NSImage(data: data)
        }
        if let img {
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
