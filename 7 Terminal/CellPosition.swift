import Foundation

/// A position in the terminal grid. Row 0 is the oldest scrollback line.
internal struct CellPosition: Hashable, Sendable {
    let row: Int
    let col: Int
}
