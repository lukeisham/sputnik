import Foundation

// MARK: - Terminal operations

/// A single parsed terminal operation emitted by `ANSIParser`.
public enum TerminalOp: Sendable {
    /// Print a single Unicode character at the current cursor position.
    case print(Character)
    /// Move cursor to absolute (0-based) position.
    case moveCursor(row: Int, col: Int)
    /// Move cursor by a relative amount (positive = down/right).
    case moveCursorRelative(rows: Int, cols: Int)
    /// Move cursor to a specific row (0-based), keeping column.
    case setCursorRow(Int)
    /// Move cursor to a specific column (0-based), keeping row.
    case setCursorCol(Int)
    /// Apply one or more SGR (Select Graphic Rendition) attributes.
    case setAttributes([SGRAttribute])
    /// Erase part of the display.
    case eraseDisplay(EraseMode)
    /// Erase part of the current line.
    case eraseLine(EraseMode)
    /// Scroll the active region up by n lines.
    case scrollUp(Int)
    /// Newline (moves cursor to next row, possibly scrolling).
    case newline
    /// Carriage return (moves cursor to column 0).
    case carriageReturn
    /// Backspace (moves cursor left one column, no erase).
    case backspace
    /// Horizontal tab.
    case tab
    /// Bell / alert.
    case bell
    /// Save cursor position.
    case saveCursor
    /// Restore cursor position.
    case restoreCursor
    /// Set the terminal window title (OSC 0/2).
    case setTitle(String)
    /// Switch to the alternate screen buffer.
    case enterAltScreen
    /// Switch back to the normal screen buffer.
    case exitAltScreen
    /// Show or hide the cursor.
    case setCursorVisible(Bool)
    /// OSC 133 A — shell prompt start marker.
    case shellPromptStart
    /// OSC 133 B — command input start (pre-exec).
    case shellCommandStart
    /// OSC 133 C — command output start.
    case shellOutputStart
    /// OSC 133 D — command finished, with optional exit code.
    case shellCommandEnd(exitCode: Int32)
}

/// How much of the display or line to erase.
public enum EraseMode: Sendable {
    case toEnd  // from cursor to end
    case toStart  // from start to cursor
    case all  // entire area
}

/// One SGR (Select Graphic Rendition) attribute.
public enum SGRAttribute: Sendable, Equatable {
    case reset
    case bold
    case dim
    case italic
    case underline
    case blink
    case inverse
    case strikethrough
    case noBold
    case noItalic
    case noUnderline
    case noInverse
    case foreground(CellColor)
    case background(CellColor)
}

// MARK: - Parser

/// Parses a raw byte stream from a PTY master fd into discrete `TerminalOp` values.
///
/// Holds only incremental parse state — no screen grid, no AppKit.
/// Feed raw `Data` via `parse(_:)` and collect the returned operations array.
/// The parser is a `struct`; make it a `var` if you need to feed data in chunks.
public struct ANSIParser {

    // MARK: - Internal state machine

    private enum State {
        case ground  // normal text
        case escape  // received ESC (0x1B)
        case csi([UInt8])  // received ESC [ — accumulating CSI bytes
        case osc(String)  // received ESC ] — accumulating OSC string
        case oscSt(String)  // OSC awaiting terminator
    }

    private var state: State = .ground

    public init() {}

    // MARK: - Public API

    /// Feed raw bytes and receive all terminal operations they represent.
    public mutating func parse(_ data: Data) -> [TerminalOp] {
        var ops = [TerminalOp]()
        for byte in data {
            let scalar = Unicode.Scalar(byte)
            process(byte: byte, scalar: scalar, into: &ops)
        }
        return ops
    }

    // MARK: - State machine

    private mutating func process(
        byte: UInt8,
        scalar: Unicode.Scalar,
        into ops: inout [TerminalOp]
    ) {
        switch state {

        case .ground:
            switch byte {
            case 0x07: ops.append(.bell)
            case 0x08: ops.append(.backspace)
            case 0x09: ops.append(.tab)
            case 0x0A, 0x0B, 0x0C: ops.append(.newline)
            case 0x0D: ops.append(.carriageReturn)
            case 0x1B: state = .escape
            default:
                if scalar.value >= 0x20 {
                    ops.append(.print(Character(scalar)))
                }
            }

        case .escape:
            switch byte {
            case 0x5B: state = .csi([])  // ESC [  → CSI
            case 0x5D: state = .osc("")  // ESC ]  → OSC
            case 0x37:
                ops.append(.saveCursor)
                state = .ground  // ESC 7
            case 0x38:
                ops.append(.restoreCursor)
                state = .ground  // ESC 8
            case 0x44:
                ops.append(.newline)
                state = .ground  // ESC D (IND)
            case 0x4D:
                ops.append(.scrollUp(1))
                state = .ground  // ESC M (RI)
            default: state = .ground
            }

        case .csi(let bytes):
            if byte >= 0x40 && byte <= 0x7E {
                // Final byte — dispatch the CSI sequence
                let finalOps = dispatchCSI(params: bytes, final: byte)
                ops.append(contentsOf: finalOps)
                state = .ground
            } else {
                state = .csi(bytes + [byte])
            }

        case .osc(let accumulated):
            if byte == 0x07 {
                // BEL terminates OSC
                ops.append(contentsOf: dispatchOSC(accumulated))
                state = .ground
            } else if byte == 0x1B {
                state = .oscSt(accumulated)
            } else {
                state = .osc(accumulated + String(scalar))
            }

        case .oscSt(let accumulated):
            // ESC \ (ST) terminates OSC
            if byte == 0x5C {
                ops.append(contentsOf: dispatchOSC(accumulated))
            }
            state = .ground
        }
    }

    // MARK: - CSI dispatch

    private func dispatchCSI(params bytes: [UInt8], final: UInt8) -> [TerminalOp] {
        let paramString = String(bytes: bytes.filter { $0 != 0x3F }, encoding: .ascii) ?? ""
        let isPrivate = bytes.first == 0x3F  // leading '?'
        let nums = parseParams(paramString)
        let p0 = nums.first ?? 0
        let p1 = nums.count > 1 ? nums[1] : 0

        switch final {

        // Cursor movement
        case 0x41: return [.moveCursorRelative(rows: -(max(p0, 1)), cols: 0)]  // CUU
        case 0x42: return [.moveCursorRelative(rows: max(p0, 1), cols: 0)]  // CUD
        case 0x43: return [.moveCursorRelative(rows: 0, cols: max(p0, 1))]  // CUF
        case 0x44: return [.moveCursorRelative(rows: 0, cols: -(max(p0, 1)))]  // CUB
        case 0x45: return [.moveCursorRelative(rows: max(p0, 1), cols: 0), .setCursorCol(0)]  // CNL
        case 0x46: return [.moveCursorRelative(rows: -(max(p0, 1)), cols: 0), .setCursorCol(0)]  // CPL
        case 0x47: return [.setCursorCol(max(p0, 1) - 1)]  // CHA
        case 0x48, 0x66:  // CUP / HVP
            return [.moveCursor(row: max(p0, 1) - 1, col: max(p1, 1) - 1)]
        case 0x64: return [.setCursorRow(max(p0, 1) - 1)]  // VPA
        case 0x73: return [.saveCursor]
        case 0x75: return [.restoreCursor]

        // Erase
        case 0x4A:  // ED
            return [.eraseDisplay(eraseMode(p0))]
        case 0x4B:  // EL
            return [.eraseLine(eraseMode(p0))]

        // SGR
        case 0x6D:
            return [.setAttributes(parseSGR(nums))]

        // DEC private modes (h/l)
        case 0x68 where isPrivate:
            return decPrivateSet(nums, on: true)
        case 0x6C where isPrivate:
            return decPrivateSet(nums, on: false)

        // Scroll
        case 0x53: return [.scrollUp(max(p0, 1))]  // SU
        case 0x54: return []  // SD — ignored for now

        default: return []
        }
    }

    private func eraseMode(_ p: Int) -> EraseMode {
        switch p {
        case 1: return .toStart
        case 2: return .all
        default: return .toEnd
        }
    }

    private func decPrivateSet(_ nums: [Int], on: Bool) -> [TerminalOp] {
        var ops = [TerminalOp]()
        for n in nums {
            switch n {
            case 25: ops.append(.setCursorVisible(on))
            case 47, 1047: ops.append(on ? .enterAltScreen : .exitAltScreen)
            case 1049: ops.append(on ? .enterAltScreen : .exitAltScreen)
            default: break
            }
        }
        return ops
    }

    // MARK: - SGR parsing

    private func parseSGR(_ nums: [Int]) -> [SGRAttribute] {
        guard !nums.isEmpty else { return [.reset] }
        var attrs = [SGRAttribute]()
        var i = 0
        while i < nums.count {
            let n = nums[i]
            switch n {
            case 0: attrs.append(.reset)
            case 1: attrs.append(.bold)
            case 2: attrs.append(.dim)
            case 3: attrs.append(.italic)
            case 4: attrs.append(.underline)
            case 5, 6: attrs.append(.blink)
            case 7: attrs.append(.inverse)
            case 9: attrs.append(.strikethrough)
            case 22: attrs.append(.noBold)
            case 23: attrs.append(.noItalic)
            case 24: attrs.append(.noUnderline)
            case 27: attrs.append(.noInverse)
            case 30...37: attrs.append(.foreground(.ansi(UInt8(n - 30))))
            case 38:
                if let (color, consumed) = parseExtendedColor(nums, at: i + 1) {
                    attrs.append(.foreground(color))
                    i += consumed
                }
            case 39: attrs.append(.foreground(.default))
            case 40...47: attrs.append(.background(.ansi(UInt8(n - 40))))
            case 48:
                if let (color, consumed) = parseExtendedColor(nums, at: i + 1) {
                    attrs.append(.background(color))
                    i += consumed
                }
            case 49: attrs.append(.background(.default))
            case 90...97: attrs.append(.foreground(.ansi(UInt8(n - 90 + 8))))
            case 100...107: attrs.append(.background(.ansi(UInt8(n - 100 + 8))))
            default: break
            }
            i += 1
        }
        return attrs
    }

    /// Parses 38/48 ; 5 ; n  or  38/48 ; 2 ; r ; g ; b  extended colour sequences.
    /// Returns the `CellColor` and the number of additional indices consumed.
    private func parseExtendedColor(_ nums: [Int], at start: Int) -> (CellColor, Int)? {
        guard start < nums.count else { return nil }
        switch nums[start] {
        case 5:
            guard start + 1 < nums.count else { return nil }
            return (.palette(UInt8(clamping: nums[start + 1])), 2)
        case 2:
            guard start + 3 < nums.count else { return nil }
            let r = Double(nums[start + 1]) / 255.0
            let g = Double(nums[start + 2]) / 255.0
            let b = Double(nums[start + 3]) / 255.0
            return (.rgb(r, g, b), 4)
        default:
            return nil
        }
    }

    // MARK: - OSC dispatch

    private func dispatchOSC(_ body: String) -> [TerminalOp] {
        // OSC 133 ; code [; exit_code] — shell-integration markers.
        if body.hasPrefix("133;") {
            let rest = String(body.dropFirst(4))
            // Split at the first semicolon: code and optional exit code.
            let parts = rest.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            let code = parts.first.map { String($0) } ?? ""
            let exitStr = parts.count > 1 ? String(parts[1]) : ""
            let exitCode = Int32(exitStr) ?? 0
            switch code {
            case "A": return [.shellPromptStart]
            case "B": return [.shellCommandStart]
            case "C": return [.shellOutputStart]
            case "D": return [.shellCommandEnd(exitCode: exitCode)]
            default: return []
            }
        }

        // OSC 0 or 2 ; <title>
        guard body.hasPrefix("0;") || body.hasPrefix("2;") else { return [] }
        let title = String(body.dropFirst(2))
        return [.setTitle(title)]
    }

    // MARK: - Helpers

    private func parseParams(_ s: String) -> [Int] {
        guard !s.isEmpty else { return [] }
        return s.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
    }
}
