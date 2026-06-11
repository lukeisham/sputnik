import AppKit

/// Draws a line-number gutter alongside the editor scroll view.
///
/// SW-3: `NSRulerView` is required for pixel-accurate gutter drawing aligned with
/// `NSLayoutManager` line fragment origins — this alignment is not achievable in SwiftUI.
/// This type has a single responsibility (line-number rendering) and is kept separate
/// from `EditorTextView` (SR-6).
public final class LineNumberRulerView: NSRulerView {

    // MARK: - Configuration

    private let gutterFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    private let gutterColor: NSColor = .tertiaryLabelColor
    private let gutterBg: NSColor = .windowBackgroundColor
    private static let padding: CGFloat = 8

    // MARK: - Init

    public init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Drawing

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        gutterBg.set()
        rect.fill()

        guard
            let textView = clientView as? NSTextView,
            let layoutMgr = textView.layoutManager,
            let textContainer = textView.textContainer,
            let textStorage = textView.textStorage
        else { return }

        let visibleRect = scrollView?.contentView.bounds ?? bounds
        let glyphRange = layoutMgr.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutMgr.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let nsText = textStorage.string as NSString
        var lineNumber = 1

        // Count newlines before the visible range to establish the starting line number.
        let precedingRange = NSRange(location: 0, length: charRange.location)
        nsText.enumerateSubstrings(
            in: precedingRange,
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in
            lineNumber += 1
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: gutterColor,
        ]

        nsText.enumerateSubstrings(
            in: charRange,
            options: [.byLines, .substringNotRequired]
        ) { [weak self] _, _, enclosingRange, stop in
            guard let self else {
                stop.pointee = true
                return
            }

            let glyphIdx = layoutMgr.glyphIndexForCharacter(at: enclosingRange.location)
            var fragRect = layoutMgr.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            fragRect = fragRect.offsetBy(dx: 0, dy: -visibleRect.minY)

            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attrs)
            let x = bounds.width - labelSize.width - Self.padding
            let y = fragRect.minY + (fragRect.height - labelSize.height) / 2
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            lineNumber += 1
        }
    }
}
