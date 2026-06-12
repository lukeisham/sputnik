import AppKit
import Foundation
import SwiftUI

/// An editable character grid that wraps an ASCII-art string and provides
/// selection, character replace, alignment, and fill operations.
///
/// Tracks a `hasManualEdits` flag so the Studio can warn before discarding
/// edits via re-conversion. Provides **⌘Z / ⌘⇧Z** undo/redo support via
/// an `UndoManager` scoped to this editor instance.
@MainActor
public final class ASCIIImageEditor: ObservableObject {

    // MARK: - Types

    /// The selection range in the flattened character grid.
    public struct Selection: Sendable, Equatable {
        public var startIndex: Int
        public var endIndex: Int

        public var range: ClosedRange<Int> {
            min(startIndex, endIndex)...max(startIndex, endIndex)
        }

        public var isEmpty: Bool { startIndex == endIndex }

        public static let empty = Selection(startIndex: 0, endIndex: 0)
    }

    // MARK: - Published state

    /// The raw character grid as a flat array (row-major).
    @Published public var grid: [Character] = []

    /// The number of columns in the grid.
    @Published public var columns: Int = 80

    /// The number of rows in the grid.
    @Published public var rows: Int = 0

    /// The current selection range.
    @Published public var selection: Selection = .empty

    /// Whether the user has made manual edits since the last conversion/load.
    /// The setter is internal so the Studio view can reset it on re-convert.
    @Published public var hasManualEdits: Bool = false

    // MARK: - Undo manager

    /// Undo manager scoped to this editor instance.
    public private(set) var undoManager: UndoManager

    // MARK: - Init

    public init() {
        self.undoManager = UndoManager()
    }

    // MARK: - Load content

    /// Loads an ASCII string into the editor, resetting the edit flag.
    /// - Parameters:
    ///   - string: The multi-line ASCII art string.
    ///   - targetColumns: The number of columns for the grid (derived from width).
    public func load(_ string: String, targetColumns: Int) {
        let lines = string.components(separatedBy: .newlines)
        columns = targetColumns
        rows = lines.count
        grid = Array(string.filter { !$0.isNewline })
        selection = .empty
        hasManualEdits = false
        // Replace the undo manager to clear all history — new content starts fresh.
        undoManager = UndoManager()

        // If grid is empty or shorter than expected, pad it.
        let expected = columns * rows
        while grid.count < expected {
            grid.append(" ")
        }
    }

    /// Returns the current grid as a newline-separated string.
    public func asString() -> String {
        guard columns > 0, rows > 0 else { return "" }
        var result = ""
        for row in 0..<rows {
            let start = row * columns
            let end = min(start + columns, grid.count)
            result += String(grid[start..<end])
            if row < rows - 1 { result += "\n" }
        }
        return result
    }

    // MARK: - Character operations

    /// Replace the character at the given index.
    /// - Parameters:
    ///   - index: The flat grid index.
    ///   - char: The new character.
    public func replaceCharacter(at index: Int, with char: Character) {
        guard index >= 0, index < grid.count else { return }
        let oldChar = grid[index]
        guard oldChar != char else { return }

        // Register undo.
        undoManager.registerUndo(withTarget: self) { editor in
            editor.replaceCharacter(at: index, with: oldChar)
        }

        grid[index] = char
        hasManualEdits = true
    }

    /// Replace multiple characters at the given indices.
    /// - Parameters:
    ///   - replacements: Array of (index, character) pairs.
    public func batchReplace(_ replacements: [(Int, Character)]) {
        guard !replacements.isEmpty else { return }
        let snapshot: [(Int, Character)] = replacements.compactMap { (index, _) in
            guard index >= 0, index < grid.count else { return nil }
            return (index, grid[index])
        }
        guard !snapshot.isEmpty else { return }

        // Register undo.
        undoManager.registerUndo(withTarget: self) { editor in
            editor.batchReplace(snapshot)
        }

        for (index, char) in replacements {
            guard index >= 0, index < grid.count else { continue }
            grid[index] = char
        }
        hasManualEdits = true
    }

    // MARK: - Editing tools

    /// Replace the selected region with `char`.
    public func replaceSelection(with char: Character) {
        guard !selection.isEmpty else { return }
        let r = selection.range
        let snapshots: [(Int, Character)] = r.map { ($0, grid[$0]) }
        undoManager.registerUndo(withTarget: self) { editor in
            editor.batchReplace(snapshots)
        }
        for i in r {
            guard i >= 0, i < grid.count else { continue }
            grid[i] = char
        }
        hasManualEdits = true
    }

    /// Align the ASCII art: pad all lines to the same width, centering
    /// or left/right aligning content within each row.
    public enum Alignment: String, CaseIterable, Sendable {
        case left = "Left"
        case center = "Center"
        case right = "Right"
    }

    /// Align the entire grid using the specified alignment strategy.
    /// Operates row-by-row, trimming trailing whitespace then re-padding.
    public func align(_ alignment: Alignment) {
        guard columns > 0, rows > 0 else { return }
        let snapshot = grid

        undoManager.registerUndo(withTarget: self) { editor in
            editor.grid = snapshot
            editor.hasManualEdits = true
        }

        for row in 0..<rows {
            let start = row * columns
            let end = min(start + columns, grid.count)
            var line = String(grid[start..<end])

            // Trim trailing whitespace.
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Re-pad to target width.
            switch alignment {
            case .left:
                line = trimmed.padding(toLength: columns, withPad: " ", startingAt: 0)
            case .center:
                let pad = columns - trimmed.count
                let leftPad = pad / 2
                line = String(repeating: " ", count: leftPad) + trimmed
                line = line.padding(toLength: columns, withPad: " ", startingAt: 0)
            case .right:
                line =
                    String(repeating: " ", count: columns - min(trimmed.count, columns)) + trimmed
                line = line.padding(toLength: columns, withPad: " ", startingAt: 0)
            }

            for (offset, char) in line.enumerated() {
                let idx = start + offset
                guard idx < grid.count else { break }
                grid[idx] = char
            }
        }
        hasManualEdits = true
    }

    /// Fill (replace) all non-space characters in the grid with `char`.
    public func fill(_ char: Character) {
        guard !grid.isEmpty else { return }
        let snapshot = grid

        undoManager.registerUndo(withTarget: self) { editor in
            editor.grid = snapshot
            editor.hasManualEdits = true
        }

        for i in grid.indices where grid[i] != " " {
            grid[i] = char
        }
        hasManualEdits = true
    }
}
