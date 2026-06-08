import AppKit
import Foundation

/// An `NSView` that draws the terminal cell grid directly with Core Text.
///
/// **SW-3 justification:** raw AppKit drawing is required here because ANSI
/// terminal rendering demands per-cell attribute control (foreground, background,
/// bold, italic, underline, inverse) at a throughput that `NSTextView` or
/// SwiftUI `Text` cannot match without prohibitive layout overhead. The
/// `NSView` is wrapped by `TerminalRenderer` (`NSViewRepresentable`) and
/// exposed to SwiftUI as an opaque view.
///
/// All drawing and key routing occurs on `@MainActor`.
@MainActor
public final class TerminalTextView: NSView {

    // MARK: - Configuration

    /// Receives encoded keystroke bytes to forward to the session.
    public var onKeyInput: ((Data) -> Void)?

    // MARK: - Display state

    private var snapshot: EmulatorSnapshot?
    private var profile:  TerminalProfile = .default

    // MARK: - Cached metrics (recomputed on profile change or resize)

    private var cellWidth:  CGFloat = 0
    private var cellHeight: CGFloat = 0
    private var font:       NSFont  = NSFont(name: "Menlo", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)

    // MARK: - Init

    public override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer      = true
        layer?.backgroundColor = NSColor.black.cgColor
        updateMetrics(for: profile)
    }

    // MARK: - Public updaters

    /// Push a new snapshot for rendering.
    public func update(snapshot: EmulatorSnapshot, profile: TerminalProfile) {
        let profileChanged = (profile != self.profile)
        self.snapshot = snapshot
        self.profile  = profile
        if profileChanged { updateMetrics(for: profile) }
        needsDisplay = true
    }

    // MARK: - Key handling

    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        // Convert NSEvent to platform-independent TerminalKeyEvent so KeyEncoder
        // remains AppKit-free (SW-3 / SR-6).
        var mods = TerminalModifiers()
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        if event.modifierFlags.contains(.shift)   { mods.insert(.shift) }
        if event.modifierFlags.contains(.option)  { mods.insert(.option) }
        if event.modifierFlags.contains(.command) { mods.insert(.command) }
        let keyEvent = TerminalKeyEvent(
            keyCode:    event.keyCode,
            characters: event.characters ?? "",
            modifiers:  mods
        )
        if let data = KeyEncoder.encode(keyEvent) {
            onKeyInput?(data)
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let snap = snapshot,
              cellWidth > 0, cellHeight > 0 else {
            // Draw background placeholder
            NSColor(terminalColor: profile.background).setFill()
            bounds.fill()
            return
        }

        let bg = NSColor(terminalColor: profile.background)
        bg.setFill()
        bounds.fill()

        let allLines: [[ScreenCell]]
        let gridOffset: Int

        // Show scrollback above the active grid
        let scrollbackLines = snap.scrollback
        let gridLines       = snap.grid
        allLines  = scrollbackLines + gridLines
        gridOffset = scrollbackLines.count

        for (lineIdx, line) in allLines.enumerated() {
            let row = CGFloat(lineIdx)
            for (colIdx, cell) in line.enumerated() {
                let col = CGFloat(colIdx)
                let cellRect = CGRect(
                    x: col  * cellWidth,
                    y: bounds.height - (row + 1) * cellHeight,
                    width:  cellWidth,
                    height: cellHeight
                )

                // Background fill
                let bgColor = resolveColor(
                    cell.style.inverse ? cell.foreground : cell.background,
                    isBackground: true
                )
                bgColor.setFill()
                ctx.fill(cellRect)

                // Glyph
                guard cell.character != " " else { continue }
                let fgColor = resolveColor(
                    cell.style.inverse ? cell.background : cell.foreground,
                    isBackground: false
                )
                let glyphFont = styledFont(bold: cell.style.bold, italic: cell.style.italic)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: glyphFont,
                    .foregroundColor: fgColor,
                    .underlineStyle: cell.style.underline
                        ? NSUnderlineStyle.single.rawValue as NSNumber : 0 as NSNumber,
                    .strikethroughStyle: cell.style.strikethrough
                        ? NSUnderlineStyle.single.rawValue as NSNumber : 0 as NSNumber,
                ]
                let str = NSAttributedString(string: String(cell.character), attributes: attrs)
                str.draw(in: cellRect)
            }
        }

        // Cursor (only in the active grid area)
        if snap.cursorVisible {
            let cursorAbsRow = gridOffset + snap.cursorRow
            let cursorRect = CGRect(
                x: CGFloat(snap.cursorCol) * cellWidth,
                y: bounds.height - CGFloat(cursorAbsRow + 1) * cellHeight,
                width:  cellWidth,
                height: cellHeight
            )
            NSColor(terminalColor: profile.foreground).withAlphaComponent(0.7).setFill()
            cursorRect.fill()
        }
    }

    // MARK: - Helpers

    private func updateMetrics(for profile: TerminalProfile) {
        let f = NSFont(name: profile.fontName, size: profile.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: profile.fontSize, weight: .regular)
        font       = f
        // Measure a monospace reference glyph
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        let size   = ("M" as NSString).size(withAttributes: attrs)
        cellWidth  = size.width
        cellHeight = size.height + 2   // small leading
    }

    private func resolveColor(_ color: CellColor, isBackground: Bool) -> NSColor {
        switch color {
        case .default:
            return isBackground
                ? NSColor(terminalColor: profile.background)
                : NSColor(terminalColor: profile.foreground)
        case .ansi(let idx) where Int(idx) < profile.ansiPalette.count:
            return NSColor(terminalColor: profile.ansiPalette[Int(idx)])
        case .ansi:
            return isBackground
                ? NSColor(terminalColor: profile.background)
                : NSColor(terminalColor: profile.foreground)
        case .palette(let idx):
            return ansi256Color(index: idx)
        case .rgb(let r, let g, let b):
            return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
        }
    }

    /// Resolves xterm 256-colour palette index to `NSColor`.
    private func ansi256Color(index: UInt8) -> NSColor {
        let i = Int(index)
        if i < 16 {
            let fallback = i < profile.ansiPalette.count ? profile.ansiPalette[i] : profile.foreground
            return NSColor(terminalColor: fallback)
        }
        if i >= 232 {
            let grey = Double(i - 232) * (1.0 / 23.0)
            return NSColor(calibratedRed: grey, green: grey, blue: grey, alpha: 1.0)
        }
        let adjusted = i - 16
        let b = adjusted % 6
        let g = (adjusted / 6) % 6
        let r = (adjusted / 36)
        let step: (Int) -> Double = { $0 == 0 ? 0 : (Double($0) * 40.0 + 55.0) / 255.0 }
        return NSColor(calibratedRed: step(r), green: step(g), blue: step(b), alpha: 1.0)
    }

    private func styledFont(bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold   { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return NSFontManager.shared.font(
            withFamily: font.familyName ?? font.fontName,
            traits: traits,
            weight: bold ? 9 : 5,
            size: font.pointSize
        ) ?? font
    }
}

// MARK: - NSColor + TerminalColor

private extension NSColor {
    convenience init(terminalColor c: TerminalColor) {
        self.init(calibratedRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
