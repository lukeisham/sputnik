import Foundation

// MARK: - Sendable snapshot

/// An immutable, `Sendable` view of the terminal grid state.
///
/// Handed from the emulator `actor` to `@MainActor` rendering code without
/// copying any non-`Sendable` types (SW-1, SR-4).
public struct EmulatorSnapshot: Sendable {
    /// Active screen grid: `grid[row][col]`.
    public let grid: [[ScreenCell]]
    /// Lines scrolled off the top of the active screen, oldest first.
    public let scrollback: [[ScreenCell]]
    /// Cursor row within the active grid (0-based).
    public let cursorRow: Int
    /// Cursor column within the active grid (0-based).
    public let cursorCol: Int
    /// Whether the cursor should be rendered.
    public let cursorVisible: Bool
    /// Current terminal title (from OSC sequences), if set.
    public let title: String?
    /// The captured output text of the last completed command (OSC 133 D).
    public let lastCommandOutput: String?
    /// Exit code from the last completed command, or 0 if none.
    public let lastCommandExitCode: Int32
}

// MARK: - Emulator actor

/// Parses raw PTY output and maintains the terminal screen grid.
///
/// An `actor` keeps all ANSI parsing and grid mutation off the main thread (SW-1).
/// Callers on `@MainActor` receive a `Sendable` `EmulatorSnapshot` for rendering
/// without any shared mutable state crossing the isolation boundary (SR-4).
public actor TerminalEmulator {

    // MARK: - Grid state

    private var cols: Int
    private var rows: Int
    private var grid: [[ScreenCell]]

    // MARK: - Cursor & attributes

    private var cursorRow: Int = 0
    private var cursorCol: Int = 0
    private var cursorVisible: Bool = true
    private var savedRow: Int = 0
    private var savedCol: Int = 0

    // MARK: - Current SGR attributes

    private var currentFG: CellColor = .default
    private var currentBG: CellColor = .default
    private var currentStyle: CellStyle = .plain

    // MARK: - Scrollback

    private var scrollback: ScrollbackBuffer

    // MARK: - Alt screen support

    private var altGrid: [[ScreenCell]]?
    private var altCursorRow: Int = 0
    private var altCursorCol: Int = 0
    private var inAltScreen: Bool = false

    // MARK: - Parser

    private var parser: ANSIParser = ANSIParser()

    // MARK: - Misc

    private var title: String?

    // MARK: - OSC 133 shell-integration command-output capture

    /// When true, printed characters and newlines are captured into `commandOutputBuffer`.
    private var capturingCommandOutput: Bool = false
    private var commandOutputBuffer: String = ""
    /// The captured text of the last finished command (set at OSC 133 D).
    private var lastCommandOutput: String? = nil
    private var lastCommandExitCode: Int32 = 0

    // MARK: - Init

    public init(cols: Int = 80, rows: Int = 24, profile: TerminalProfile = .default) {
        self.cols = cols
        self.rows = rows
        self.grid = TerminalEmulator.emptyGrid(cols: cols, rows: rows)
        self.scrollback = ScrollbackBuffer(capacity: profile.scrollbackLineLimit)
    }

    // MARK: - Feed

    /// Feed raw bytes from the PTY master into the emulator.
    public func feed(_ data: Data) {
        let ops = parser.parse(data)
        for op in ops {
            apply(op)
        }
    }

    // MARK: - Resize

    /// Resize the active grid. Existing content is preserved where possible.
    public func resize(cols newCols: Int, rows newRows: Int) {
        guard newCols > 0 && newRows > 0 else { return }
        var newGrid = TerminalEmulator.emptyGrid(cols: newCols, rows: newRows)
        for r in 0..<min(rows, newRows) {
            for c in 0..<min(cols, newCols) {
                newGrid[r][c] = grid[r][c]
            }
        }
        cols = newCols
        rows = newRows
        grid = newGrid
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
    }

    // MARK: - Snapshot

    /// Returns the current rendering snapshot.
    ///
    /// Safe to call from `@MainActor` — the returned value is fully `Sendable`.
    public func snapshot() -> EmulatorSnapshot {
        EmulatorSnapshot(
            grid: grid,
            scrollback: scrollback.lines(),
            cursorRow: cursorRow,
            cursorCol: cursorCol,
            cursorVisible: cursorVisible,
            title: title,
            lastCommandOutput: lastCommandOutput,
            lastCommandExitCode: lastCommandExitCode
        )
    }

    /// Clears the screen and resets cursor.
    public func reset() {
        grid = TerminalEmulator.emptyGrid(cols: cols, rows: rows)
        cursorRow = 0
        cursorCol = 0
        currentFG = .default
        currentBG = .default
        currentStyle = .plain
        scrollback.clear()
    }

    // MARK: - Op application

    private func apply(_ op: TerminalOp) {
        // ---- OSC 133 shell-integration capture ----
        if case .print(let ch) = op, capturingCommandOutput {
            commandOutputBuffer.append(ch)
        }
        if case .newline = op, capturingCommandOutput {
            commandOutputBuffer.append("\n")
        }

        switch op {

        case .shellPromptStart:
            // OSC 133 A — prompt begins. No capture action.
            break

        case .shellCommandStart:
            // OSC 133 B — command input starts. Discard any stale capture.
            capturingCommandOutput = false
            commandOutputBuffer = ""

        case .shellOutputStart:
            // OSC 133 C — command output begins. Start capturing.
            capturingCommandOutput = true
            commandOutputBuffer = ""

        case .shellCommandEnd(let exitCode):
            // OSC 133 D — command finished.
            capturingCommandOutput = false
            lastCommandOutput = commandOutputBuffer
            lastCommandExitCode = exitCode

        case .print(let ch):
            if cursorCol >= cols {
                // Soft-wrap: move to next line
                carriageReturn()
                lineFeed()
            }
            grid[cursorRow][cursorCol] = ScreenCell(
                character: ch,
                foreground: currentFG,
                background: currentBG,
                style: currentStyle
            )
            cursorCol += 1

        case .newline:
            lineFeed()

        case .carriageReturn:
            carriageReturn()

        case .backspace:
            if cursorCol > 0 { cursorCol -= 1 }

        case .tab:
            let nextTab = ((cursorCol / 8) + 1) * 8
            cursorCol = min(nextTab, cols - 1)

        case .bell:
            break  // audible/visual bell out of scope

        case .moveCursor(let row, let col):
            cursorRow = clampRow(row)
            cursorCol = clampCol(col)

        case .moveCursorRelative(let dr, let dc):
            cursorRow = clampRow(cursorRow + dr)
            cursorCol = clampCol(cursorCol + dc)

        case .setCursorRow(let row):
            cursorRow = clampRow(row)

        case .setCursorCol(let col):
            cursorCol = clampCol(col)

        case .setAttributes(let attrs):
            applyAttributes(attrs)

        case .eraseDisplay(let mode):
            eraseDisplay(mode)

        case .eraseLine(let mode):
            eraseLine(mode)

        case .scrollUp(let n):
            for _ in 0..<n { scrollUpOneLine() }

        case .saveCursor:
            savedRow = cursorRow
            savedCol = cursorCol

        case .restoreCursor:
            cursorRow = clampRow(savedRow)
            cursorCol = clampCol(savedCol)

        case .setTitle(let t):
            title = t

        case .enterAltScreen:
            guard !inAltScreen else { break }
            altGrid = grid
            altCursorRow = cursorRow
            altCursorCol = cursorCol
            grid = TerminalEmulator.emptyGrid(cols: cols, rows: rows)
            cursorRow = 0
            cursorCol = 0
            inAltScreen = true

        case .exitAltScreen:
            guard inAltScreen else { break }
            if let saved = altGrid { grid = saved }
            cursorRow = clampRow(altCursorRow)
            cursorCol = clampCol(altCursorCol)
            altGrid = nil
            inAltScreen = false

        case .setCursorVisible(let visible):
            cursorVisible = visible
        }
    }

    // MARK: - Grid helpers

    private func lineFeed() {
        if cursorRow < rows - 1 {
            cursorRow += 1
        } else {
            scrollUpOneLine()
        }
    }

    private func carriageReturn() {
        cursorCol = 0
    }

    /// Scrolls the active grid up one line, pushing the vacated top row into
    /// the scrollback ring buffer (SR-3).
    private func scrollUpOneLine() {
        scrollback.append(grid[0])
        grid.removeFirst()
        grid.append([ScreenCell](repeating: ScreenCell(), count: cols))
    }

    private func eraseDisplay(_ mode: EraseMode) {
        let blank = ScreenCell(foreground: currentFG, background: currentBG)
        switch mode {
        case .toEnd:
            for c in cursorCol..<cols { grid[cursorRow][c] = blank }
            for r in (cursorRow + 1)..<rows {
                grid[r] = [ScreenCell](repeating: blank, count: cols)
            }
        case .toStart:
            for c in 0...cursorCol { grid[cursorRow][c] = blank }
            for r in 0..<cursorRow {
                grid[r] = [ScreenCell](repeating: blank, count: cols)
            }
        case .all:
            grid = TerminalEmulator.emptyGrid(cols: cols, rows: rows)
        }
    }

    private func eraseLine(_ mode: EraseMode) {
        let blank = ScreenCell(foreground: currentFG, background: currentBG)
        switch mode {
        case .toEnd:
            for c in cursorCol..<cols { grid[cursorRow][c] = blank }
        case .toStart:
            for c in 0...cursorCol { grid[cursorRow][c] = blank }
        case .all:
            grid[cursorRow] = [ScreenCell](repeating: blank, count: cols)
        }
    }

    private func applyAttributes(_ attrs: [SGRAttribute]) {
        for attr in attrs {
            switch attr {
            case .reset:
                currentFG = .default
                currentBG = .default
                currentStyle = .plain
            case .bold: currentStyle.bold = true
            case .dim: currentStyle.dim = true
            case .italic: currentStyle.italic = true
            case .underline: currentStyle.underline = true
            case .blink: currentStyle.blink = true
            case .inverse: currentStyle.inverse = true
            case .strikethrough: currentStyle.strikethrough = true
            case .noBold:
                currentStyle.bold = false
                currentStyle.dim = false
            case .noItalic: currentStyle.italic = false
            case .noUnderline: currentStyle.underline = false
            case .noInverse: currentStyle.inverse = false
            case .foreground(let c): currentFG = c
            case .background(let c): currentBG = c
            }
        }
    }

    private func clampRow(_ r: Int) -> Int { max(0, min(r, rows - 1)) }
    private func clampCol(_ c: Int) -> Int { max(0, min(c, cols - 1)) }

    private static func emptyGrid(cols: Int, rows: Int) -> [[ScreenCell]] {
        [[ScreenCell]](
            repeating: [ScreenCell](repeating: ScreenCell(), count: cols),
            count: rows
        )
    }
}
