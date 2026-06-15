import AppKit
import SwiftUI

/// An `NSView` that draws minimap line bars and a draggable viewport indicator.
///
/// Content- and target-agnostic — receives a `MinimapModel` and a viewport fraction,
/// reports user interactions (click / drag) through a callback.
///
/// **AppKit bridge rationale (SW-3):** Per-pixel drawing and mouse hit-testing for a
/// draggable viewport exceed SwiftUI `Canvas` ergonomics. `NSView` gives us
/// `mouseDown` / `mouseDragged` with zero latency and no gesture-recognizer overhead.
public final class MinimapView: NSView {

    // MARK: - Input

    /// The model to draw. Set on the main thread.
    var model: MinimapModel = .empty {
        didSet { needsDisplay = true }
    }

    /// The viewport fraction (0 = top, 1 = bottom). Set on the main thread.
    var viewportFraction: Double = 0 {
        didSet {
            if abs(viewportFraction - oldValue) > 0.001 {
                needsDisplay = true
            }
        }
    }

    /// Opacity of the minimap overlay. Applies to the entire view.
    var minimapOpacity: Double = 0.55 {
        didSet { needsDisplay = true }
    }

    // MARK: - Callback

    /// Called when the user clicks or drags the viewport indicator.
    /// The parameter is the target scroll fraction (0 … 1).
    var onScrollToFraction: ((Double) -> Void)?

    // MARK: - Constants

    private enum Constants {
        static let barMaxWidth: CGFloat = 80
        static let barMinWidth: CGFloat = 4
        static let barSpacing: CGFloat = 1.5
        static let viewportCornerRadius: CGFloat = 3
        static let viewportMinHeight: CGFloat = 12
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let lines = model.lines
        guard !lines.isEmpty else { return }

        let bounds = self.bounds
        let totalHeight = bounds.height
        let barAreaWidth = bounds.width

        // Each line gets equal vertical space.
        let lineHeight = totalHeight / CGFloat(lines.count)
        let spacing = Constants.barSpacing

        // Cache bar colours to avoid NSColor→CGColor per line.
        let barColors: [LineKind: CGColor] = [
            .plain: SputnikColor.minimapPlain.cgColor ?? CGColor(gray: 0.5, alpha: 1),
            .blank: SputnikColor.minimapBlank.cgColor ?? CGColor(gray: 0.3, alpha: 1),
            .heading: SputnikColor.minimapHeading.cgColor
                ?? CGColor(red: 0.15, green: 0.42, blue: 0.72, alpha: 1),
            .code: SputnikColor.minimapCode.cgColor
                ?? CGColor(red: 0.62, green: 0.35, blue: 0.15, alpha: 1),
            .quote: SputnikColor.minimapQuote.cgColor
                ?? CGColor(red: 0.55, green: 0.45, blue: 0.12, alpha: 1),
            .list: SputnikColor.minimapList.cgColor
                ?? CGColor(red: 0.28, green: 0.55, blue: 0.18, alpha: 1),
        ]

        context.setAlpha(CGFloat(minimapOpacity))

        // Draw bars.
        for (index, line) in lines.enumerated() {
            let y = totalHeight - (CGFloat(index) + 1) * lineHeight  // flip Y for AppKit
            let barHeight = max(lineHeight - spacing, 0.5)
            let width = max(
                Constants.barMinWidth,
                CGFloat(line.lengthFraction) * barAreaWidth
            )
            let rect = CGRect(x: 0, y: y, width: min(width, barAreaWidth), height: barHeight)

            if let cg = barColors[line.kind] {
                context.setFillColor(cg)
                context.fill(rect)
            }
        }

        // Draw viewport indicator.
        let viewportY = totalHeight * CGFloat(1.0 - viewportFraction) - viewportIndicatorHeight / 2
        let clampedY = max(0, min(viewportY, totalHeight - viewportIndicatorHeight))

        let vpRect = CGRect(
            x: 0, y: clampedY,
            width: barAreaWidth,
            height: viewportIndicatorHeight
        )
        let vpPath = NSBezierPath(
            roundedRect: vpRect,
            xRadius: Constants.viewportCornerRadius,
            yRadius: Constants.viewportCornerRadius
        )

        if let vpColor = SputnikColor.minimapViewport.cgColor {
            context.setFillColor(vpColor)
        }
        vpPath.fill()
    }

    /// Computed height of the viewport indicator rectangle.
    /// Proportional to the visible portion of the content, with a minimum.
    private var viewportIndicatorHeight: CGFloat {
        let lines = model.lines
        guard lines.count > 0 else { return Constants.viewportMinHeight }
        let visibleFraction = min(1.0, self.bounds.height / 20.0)  // approximate
        return max(
            Constants.viewportMinHeight,
            self.bounds.height * CGFloat(visibleFraction)
        )
    }

    // MARK: - Hit testing & interaction

    public override func mouseDown(with event: NSEvent) {
        handleMouse(at: event.locationInWindow, dragged: false)
    }

    public override func mouseDragged(with event: NSEvent) {
        handleMouse(at: event.locationInWindow, dragged: true)
    }

    private func handleMouse(at windowPoint: NSPoint, dragged: Bool) {
        let local = convert(windowPoint, from: nil)
        let fraction = 1.0 - (local.y / bounds.height)  // flip Y
        let clamped = max(0, min(1.0, fraction))
        onScrollToFraction?(clamped)
    }
}

// MARK: - Color → CGColor helper

extension Color {
    /// Returns a `CGColor` for the current appearance, or `nil` on failure.
    fileprivate var cgColor: CGColor? {
        NSColor(self).usingColorSpace(.deviceRGB)?.cgColor
    }
}
