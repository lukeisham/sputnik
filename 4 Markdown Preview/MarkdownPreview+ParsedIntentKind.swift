import Foundation

// MARK: - PresentationIntent styling types

/// Font sizes (in points) for Markdown heading levels (1…6).
internal let headingFontSizes: [CGFloat] = [28, 22, 18, 16, 14, 13]

/// A lightweight Swift-side snapshot of a `PresentationIntent` kind and its
/// character range. Collected from `AttributedString.runs` before bridging to
/// `NSAttributedString`, so we avoid referencing the Objective-C `NSPresentationIntent`
/// type entirely.
internal enum ParsedIntentKind: Equatable {
    case header(level: Int)
    case codeBlock
    case blockQuote
    case unorderedList
    case orderedList
    case listItem
    case table
    case tableCell
}
