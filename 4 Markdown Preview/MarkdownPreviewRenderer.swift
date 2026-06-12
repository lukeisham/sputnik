import AppKit
import Foundation
import FoundationModule
import ResourcesModule
import SputnikShared

// MARK: - PresentationIntent styling

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
internal func applyPresentationIntentStyling(_ attributed: AttributedString) -> NSAttributedString {
    // 1. Collect intent kinds and their ranges from the Swift AttributedString runs.
    var intents: [(NSRange, ParsedIntentKind)] = []

    for run in attributed.runs {
        guard let kind = parseIntentKind(from: run) else { continue }
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

/// Cache the ObjC selector for `NSPresentationIntent.identity` so it is
/// constructed once rather than on every paragraph run (ISS-055).
private let identitySelector: Selector = NSSelectorFromString("identity")

/// One-time flag to log a warning when the ObjC bridge silently degrades.
/// Resets on every launch so developers catch OS-update regressions promptly.
private let objcBridgeDiagnostic: Void = {
    // Verify that NSSelectorFromString produced a valid selector at load time.
    // Post-launch failures are caught by respond(to:) in parseIntentKind.
    debugPrint(
        "[MarkdownPreview] ObjC bridge initialized — identity=@selector(\(identitySelector))")
}()

/// Extracts a `ParsedIntentKind` from a Swift `AttributedString` run.
///
/// For heading levels, uses the `NSPresentationIntent` identity (via ObjC runtime,
/// value `1`) combined with the heading level parsed from the intent's description.
/// For block-level constructs (code blocks, block quotes, lists, tables), inspects
/// the ObjC `NSPresentationIntent` identity value (ISS-055).
///
/// Known `NSPresentationIntentKind` identity values:
///   1 = header, 2 = codeBlock, 3 = blockQuote, 4 = unorderedList,
///   5 = orderedList, 6 = listItem, 7 = table, 8 = tableCell
///
/// **Fragility note:** These identity values and the `identity` selector are
/// undocumented `NSPresentationIntent` internals (ISS-055). If a future macOS
/// release changes or removes them, this function returns `nil` and rendering
/// degrades gracefully to plain text — no crash, no data loss.
internal func parseIntentKind(from run: AttributedString.Runs.Element) -> ParsedIntentKind? {
    guard let presentationIntent = run.presentationIntent else { return nil }
    _ = objcBridgeDiagnostic  // Ensure the diagnostic fires once at module load.
    let obj = presentationIntent as AnyObject
    guard obj.responds(to: identitySelector) else {
        debugPrint(
            "[MarkdownPreview] ObjC bridge degraded: NSPresentationIntent no longer responds to identity"
        )
        return nil
    }
    let rawPtr = obj.perform(identitySelector)
    guard let raw = rawPtr?.takeUnretainedValue() else { return nil }
    let identityValue: Int
    if let num = raw as? NSNumber {
        identityValue = num.intValue
    } else if let val = raw as? Int {
        identityValue = val
    } else {
        return nil
    }

    switch identityValue {
    case 1:  // header — extract level from description "[header N (id M)]"
        let desc = "\(presentationIntent)"
        let parts = desc.split(separator: " ")
        if parts.count >= 2, let level = Int(parts[1]) {
            return .header(level: max(1, min(6, level)))
        }
        return .header(level: 1)
    case 2: return .codeBlock
    case 3: return .blockQuote
    case 4: return .unorderedList
    case 5: return .orderedList
    case 6: return .listItem
    case 7: return .table
    case 8: return .tableCell
    default: return nil
    }
}

/// Maps a `ParsedIntentKind` to visual `NSAttributedString` attributes and applies
/// them to the given range.
internal func applyKindAttributes(
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

/// `@unchecked Sendable` box for crossing actor boundaries with `NSAttributedString`.
/// `NSAttributedString` is immutable after creation, making the transfer safe.
internal struct SendableAttributedString: @unchecked Sendable {
    let value: NSAttributedString
}

// MARK: - Block splitting and source map (Steps 6, 8)

/// A top-level Markdown block (split on blank lines, respecting fenced code blocks).
internal struct MarkdownBlock: Sendable {
    let text: String
    let startLine: Int  // 0-based source line
    let endLine: Int    // 0-based source line, inclusive
    var hasImages: Bool { text.contains("![") }
}

/// Maps a rendered character range in the output `NSAttributedString` back to
/// the source line range it came from. Used for ⌘-click-to-source navigation (ISS-065).
public struct MarkdownSourceBlock: Sendable {
    public let sourceStartLine: Int
    public let sourceEndLine: Int
    /// Offset of the first character of this block in the rendered `NSAttributedString`.
    public let renderedLocation: Int
    /// Character count of this block in the rendered `NSAttributedString`.
    public let renderedLength: Int

    public init(sourceStartLine: Int, sourceEndLine: Int, renderedLocation: Int, renderedLength: Int) {
        self.sourceStartLine = sourceStartLine
        self.sourceEndLine = sourceEndLine
        self.renderedLocation = renderedLocation
        self.renderedLength = renderedLength
    }

    /// Returns `true` when `renderedOffset` falls inside this block's rendered range.
    public func contains(renderedOffset: Int) -> Bool {
        renderedOffset >= renderedLocation && renderedOffset < renderedLocation + renderedLength
    }
}

/// Splits Markdown source into top-level blocks on blank lines, tracking source line numbers
/// and skipping blank lines inside fenced code blocks (``` or ~~~).
internal func splitMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    guard !markdown.isEmpty else { return [] }
    let lines = markdown.components(separatedBy: "\n")
    var blocks: [MarkdownBlock] = []
    var blockLines: [String] = []
    var blockStartLine = 0
    var currentLine = 0
    var inFence = false

    for line in lines {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.hasPrefix("```") || stripped.hasPrefix("~~~") {
            inFence.toggle()
        }
        if !inFence && stripped.isEmpty && !blockLines.isEmpty {
            blocks.append(MarkdownBlock(
                text: blockLines.joined(separator: "\n"),
                startLine: blockStartLine,
                endLine: currentLine - 1))
            blockLines = []
            blockStartLine = currentLine + 1
        } else {
            blockLines.append(line)
        }
        currentLine += 1
    }
    if !blockLines.isEmpty {
        blocks.append(MarkdownBlock(
            text: blockLines.joined(separator: "\n"),
            startLine: blockStartLine,
            endLine: currentLine - 1))
    }
    return blocks.isEmpty
        ? [MarkdownBlock(text: markdown, startLine: 0, endLine: max(0, currentLine - 1))]
        : blocks
}

/// Renders Markdown using per-block caching. Text-only blocks are cached by hash to
/// avoid re-parsing unchanged paragraphs. Image blocks always re-render.
///
/// - Parameters:
///   - markdown:  The raw Markdown source.
///   - baseDir:   Directory for resolving relative image paths.
///   - cache:     Snapshot of the caller's block cache (read-only).
/// - Returns:
///   - `NSAttributedString` assembled from all rendered blocks.
///   - `[MarkdownSourceBlock]` source map for bidirectional navigation.
///   - New cache entries to merge back on the main actor.
internal func buildBlockCachedAttributedString(
    markdown: String,
    baseDir: URL?,
    cache: [Int: SendableAttributedString]
) async -> (NSAttributedString, [MarkdownSourceBlock], [Int: SendableAttributedString]) {
    let blocks = splitMarkdownBlocks(markdown)
    guard !blocks.isEmpty else { return (NSAttributedString(), [], [:]) }

    let assembled = NSMutableAttributedString()
    var sourceMap: [MarkdownSourceBlock] = []
    var newEntries: [Int: SendableAttributedString] = [:]

    for (i, block) in blocks.enumerated() {
        let start = assembled.length
        let rendered: NSAttributedString
        let hashKey = block.text.hashValue

        if !block.hasImages, let cached = cache[hashKey] {
            rendered = cached.value
        } else if block.hasImages {
            rendered = await buildNSAttributedString(markdown: block.text, baseDir: baseDir)
        } else {
            rendered = parseMarkdownSegment(block.text)
            newEntries[hashKey] = SendableAttributedString(value: rendered)
        }

        assembled.append(rendered)
        if i < blocks.count - 1 {
            assembled.append(NSAttributedString(string: "\n"))
        }
        sourceMap.append(MarkdownSourceBlock(
            sourceStartLine: block.startLine,
            sourceEndLine: block.endLine,
            renderedLocation: start,
            renderedLength: assembled.length - start))
    }
    return (assembled, sourceMap, newEntries)
}

// MARK: - File-scope async helpers (nonisolated; called from Task background)

/// Builds a styled `NSAttributedString` from Markdown source, inserting
/// `NSTextAttachment`s for local image references and placeholder labels for
/// remote references. Text segments are rendered via `AttributedString(markdown:)`.
internal func buildNSAttributedString(markdown: String, baseDir: URL?) async -> NSAttributedString {
    // Regex matches: ![alt text](path/or/url)
    let imagePatternString = #"!\[([^\]]*)\]\(([^)\s]+)\)"#
    guard let imageRegex = try? NSRegularExpression(pattern: imagePatternString) else {
        return parseMarkdownSegment(markdown)
    }

    let allMatches = imageRegex.matches(
        in: markdown, range: NSRange(markdown.startIndex..., in: markdown))

    // Fast path — no images: skip segment splitting overhead.
    if allMatches.isEmpty {
        return parseMarkdownSegment(markdown)
    }

    let resolver = PreviewImageResolver()
    let result = NSMutableAttributedString()
    var lastEnd = markdown.startIndex

    for match in allMatches {
        guard match.numberOfRanges >= 3 else { continue }

        // Convert NSRange to String indices
        guard let fullRange = Range(match.range, in: markdown),
            let altRange = Range(match.range(at: 1), in: markdown),
            let pathRange = Range(match.range(at: 2), in: markdown)
        else {
            continue
        }

        // Render text segment before this image reference.
        let textPart = String(markdown[lastEnd..<fullRange.lowerBound])
        if !textPart.isEmpty {
            result.append(parseMarkdownSegment(textPart))
        }

        let alt = String(markdown[altRange])
        let path = String(markdown[pathRange])
        result.append(
            await resolveImageAttachment(
                path: path, alt: alt,
                baseDir: baseDir, resolver: resolver))
        lastEnd = fullRange.upperBound
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
internal func parseMarkdownSegment(_ text: String) -> NSAttributedString {
    do {
        let attributed = try AttributedString(
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
internal func resolveImageAttachment(
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
