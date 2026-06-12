import AppKit
import Foundation
import FoundationModule

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

    /// Receives grid dimensions computed from the view's bounds and cell metrics.
    /// Fires on frame change with de-duplication. Guarded against zero metrics.
    public var onResize: ((UInt16, UInt16) -> Void)?

    // MARK: - Display state

    private var snapshot: EmulatorSnapshot?
    private var profile: TerminalProfile = .default

    /// Throttles rapid snapshot updates to prevent frame drops during output floods (SR-4).
    private let renderThrottle = RenderThrottle(delay: 0.05)

    // MARK: - Cached metrics (recomputed on profile change or resize)

    private var cellWidth: CGFloat = 0
    private var cellHeight: CGFloat = 0
    private var font: NSFont =
        NSFont(name: "Menlo", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)

    // MARK: - Resize de-duplication

    private var lastReportedCols: UInt16 = 0
    private var lastReportedRows: UInt16 = 0

    // MARK: - Selection state

    /// The cell position where the selection drag started (anchor).
    private var selectionStart: CellPosition?
    /// The current cell position of the selection drag (active end).
    private var selectionEnd: CellPosition?

    /// The set of cell positions currently selected, computed from `selectionStart` and `selectionEnd`.
    private var selectedCells: Set<CellPosition>? {
        guard let start = selectionStart, let end = selectionEnd else { return nil }
        let rowStart = min(start.row, end.row)
        let rowEnd = max(start.row, end.row)
        var cells = Set<CellPosition>()
        for row in rowStart...rowEnd {
            let colStart: Int
            let colEnd: Int
            if row == rowStart && row == rowEnd {
                // Single row: clamp to the dragged column range.
                colStart = min(start.col, end.col)
                colEnd = max(start.col, end.col)
            } else if row == rowStart {
                // First row: from the start column to the right edge.
                colStart = min(start.col, end.col)
                colEnd = Int(lastReportedCols) - 1
            } else if row == rowEnd {
                // Last row: from the left edge to the end column.
                colStart = 0
                colEnd = max(start.col, end.col)
            } else {
                // Full intermediate row.
                colStart = 0
                colEnd = Int(lastReportedCols) - 1
            }
            for col in colStart...colEnd {
                cells.insert(CellPosition(row: row, col: col))
            }
        }
        return cells
    }

    // MARK: - Frame observation

    private var frameObserver: NSObjectProtocol?

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
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        postsFrameChangedNotifications = true
        updateMetrics(for: profile)
    }

    deinit {
        if let obs = frameObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Public updaters

    /// Push a new snapshot for rendering, throttled to coalesce rapid updates (SR-4).
    public func update(snapshot: EmulatorSnapshot, profile: TerminalProfile) {
        let capturedSnapshot = snapshot
        let capturedProfile = profile
        renderThrottle.throttle { [weak self] in
            guard let self else { return }
            await MainActor.run {
                let profileChanged = (capturedProfile != self.profile)
                if self.snapshot != nil {
                    // Clear selection on new output — the grid has scrolled.
                    self.selectionStart = nil
                    self.selectionEnd = nil
                }
                self.snapshot = capturedSnapshot
                self.profile = capturedProfile
                if profileChanged {
                    self.updateMetrics(for: capturedProfile)
                    self.reportGridSize()
                }
                self.needsDisplay = true
            }
        }
    }

    // MARK: - First responder (focus)

    public override var acceptsFirstResponder: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
            // Observe frame changes for resize emission.
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: self,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reportGridSize()
                }
            }
        } else {
            if let obs = frameObserver {
                NotificationCenter.default.removeObserver(obs)
                frameObserver = nil
            }
        }
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pos = cellPosition(for: event)
        selectionStart = pos
        selectionEnd = pos
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let pos = cellPosition(for: event)
        selectionEnd = pos
        needsDisplay = true
    }

    // MARK: - Key handling

    public override func keyDown(with event: NSEvent) {
        // Intercept Command+C for copy before KeyEncoder.
        if event.modifierFlags.contains(.command),
            event.charactersIgnoringModifiers == "c"
        {
            copySelectionToPasteboard()
            return
        }

        // Intercept Command+V for paste before KeyEncoder.
        if event.modifierFlags.contains(.command),
            event.charactersIgnoringModifiers == "v"
        {
            pasteFromPasteboard()
            return
        }

        // Escape clears the selection but still forwards to the shell.
        if event.keyCode == 53 {
            selectionStart = nil
            selectionEnd = nil
            needsDisplay = true
            // Fall through — still send Escape to Zsh.
        }

        // Convert NSEvent to platform-independent TerminalKeyEvent so KeyEncoder
        // remains AppKit-free (SW-3 / SR-6).
        var mods = TerminalModifiers()
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
        if event.modifierFlags.contains(.option) { mods.insert(.option) }
        if event.modifierFlags.contains(.command) { mods.insert(.command) }
        let keyEvent = TerminalKeyEvent(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            modifiers: mods
        )
        if let data = KeyEncoder.encode(keyEvent) {
            onKeyInput?(data)
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
            let snap = snapshot,
            cellWidth > 0, cellHeight > 0
        else {
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
        let gridLines = snap.grid
        allLines = scrollbackLines + gridLines
        gridOffset = scrollbackLines.count

        for (lineIdx, line) in allLines.enumerated() {
            let row = CGFloat(lineIdx)
            for (colIdx, cell) in line.enumerated() {
                let col = CGFloat(colIdx)
                let cellRect = CGRect(
                    x: col * cellWidth,
                    y: bounds.height - (row + 1) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )

                // Background fill
                let bgColor = resolveColor(
                    cell.style.inverse ? cell.foreground : cell.background,
                    isBackground: true
                )
                bgColor.setFill()
                ctx.fill(cellRect)

                // Selection highlight
                if selectedCells?.contains(CellPosition(row: lineIdx, col: colIdx)) == true {
                    NSColor.selectedTextBackgroundColor.withAlphaComponent(0.4).setFill()
                    ctx.fill(cellRect)
                }

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
                width: cellWidth,
                height: cellHeight
            )
            NSColor(terminalColor: profile.foreground).withAlphaComponent(0.7).setFill()
            cursorRect.fill()
        }
    }

    // MARK: - Grid size computation

    /// Computes cols/rows from the current bounds and cached cell metrics,
    /// then fires `onResize` if the values have changed.
    private func reportGridSize() {
        guard cellWidth > 0, cellHeight > 0 else { return }
        let cols = UInt16(floor(bounds.width / cellWidth))
        let rows = UInt16(floor(bounds.height / cellHeight))
        guard cols > 0, rows > 0 else { return }
        guard cols != lastReportedCols || rows != lastReportedRows else { return }
        lastReportedCols = cols
        lastReportedRows = rows
        onResize?(cols, rows)
    }

    // MARK: - Helpers

    // MARK: - Selection helpers

    /// Converts an `NSEvent` location to cell coordinates in the grid.
    private func cellPosition(for event: NSEvent) -> CellPosition {
        let point = convert(event.locationInWindow, from: nil)
        let col = Int(max(0, min(point.x / cellWidth, CGFloat(lastReportedCols) - 1)))
        let row = Int(max(0, min((bounds.height - point.y) / cellHeight, totalLines - 1)))
        return CellPosition(row: row, col: col)
    }

    /// Total lines in the current snapshot (scrollback + active grid).
    private var totalLines: CGFloat {
        guard let snap = snapshot else { return 0 }
        return CGFloat(snap.scrollback.count + snap.grid.count)
    }

    /// Copies the currently selected cell range to the system pasteboard as plain text.
    private func copySelectionToPasteboard() {
        guard let selected = selectedCells,
            let snap = snapshot,
            !selected.isEmpty
        else { return }

        let grid = snap.scrollback + snap.grid
        let sorted = selected.sorted { $0.row != $1.row ? $0.row < $1.row : $0.col < $1.col }

        var lines: [String] = []
        var currentRow = -1
        var currentLine = ""

        for pos in sorted {
            if pos.row != currentRow {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                }
                currentRow = pos.row
                currentLine = ""
            }
            if pos.row < grid.count, pos.col < grid[pos.row].count {
                let cell = grid[pos.row][pos.col]
                currentLine.append(cell.character)
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Reads plain text from the system pasteboard and forwards it to the shell.
    private func pasteFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
            let data = text.data(using: .utf8)
        else { return }
        onKeyInput?(data)
    }

    // MARK: - Metric helpers

    private func updateMetrics(for profile: TerminalProfile) {
        let f =
            NSFont(name: profile.fontName, size: profile.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: profile.fontSize, weight: .regular)
        font = f
        // Measure a monospace reference glyph
        let attrs: [NSAttributedString.Key: Any] = [.font: f]
        let size = ("M" as NSString).size(withAttributes: attrs)
        cellWidth = size.width
        cellHeight = size.height + 2  // small leading
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
            let fallback =
                i < profile.ansiPalette.count ? profile.ansiPalette[i] : profile.foreground
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
        if bold { traits.insert(.boldFontMask) }
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

extension NSColor {
    fileprivate convenience init(terminalColor c: TerminalColor) {
        self.init(calibratedRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
