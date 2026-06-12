import AppKit
import Foundation
import FoundationModule
import ResourcesModule

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
internal func parseIntentKind(from run: AttributedString.Runs.Element) -> ParsedIntentKind? {
    guard let presentationIntent = run.presentationIntent else { return nil }
    let obj = presentationIntent as AnyObject
    let identitySel = NSSelectorFromString("identity")
    guard obj.responds(to: identitySel) else { return nil }
    let raw = obj.perform(identitySel).takeUnretainedValue()
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
