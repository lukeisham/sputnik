import AppKit
import SwiftUI

// NSViewRepresentable because SwiftUI Canvas cannot handle per-character click
// hit-testing at the required granularity without significant complexity (SW-3).
struct MonoGridView: NSViewRepresentable {
    @ObservedObject var editor: ASCIIImageEditor

    func makeNSView(context: Context) -> GridNSView {
        let view = GridNSView()
        view.onCellTap = { row, col in
            editor.selectCell(row: row, col: col)
        }
        return view
    }

    func updateNSView(_ nsView: GridNSView, context: Context) {
        nsView.grid = editor.grid
        nsView.columns = editor.columns
        nsView.rows = editor.rows
        nsView.selectedCell = editor.selectedCell
        nsView.invalidateIntrinsicContentSize()
        nsView.needsDisplay = true
    }
}

// MARK: - GridNSView

final class GridNSView: NSView {
    var grid: [Character] = []
    var columns: Int = 0
    var rows: Int = 0
    var selectedCell: (row: Int, col: Int)? = nil
    var onCellTap: ((Int, Int) -> Void)?

    private let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
    private var cellSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        computeCellSize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        computeCellSize()
    }

    // Y increases downward, matching row ordering.
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: cellSize.width * CGFloat(columns),
            height: cellSize.height * CGFloat(rows)
        )
    }

    private func computeCellSize() {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        cellSize = ("M" as NSString).size(withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard columns > 0, rows > 0 else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        for row in 0..<rows {
            for col in 0..<columns {
                let index = row * columns + col
                guard index < grid.count else { continue }

                let x = CGFloat(col) * cellSize.width
                let y = CGFloat(row) * cellSize.height
                let cellRect = CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)

                if let sel = selectedCell, sel.row == row, sel.col == col {
                    NSColor.selectedTextBackgroundColor.withAlphaComponent(0.4).setFill()
                    cellRect.fill()
                }

                (String(grid[index]) as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard cellSize.width > 0, cellSize.height > 0 else { return }
        let col = Int(point.x / cellSize.width)
        let row = Int(point.y / cellSize.height)
        guard row >= 0, row < rows, col >= 0, col < columns else { return }
        onCellTap?(row, col)
    }
}
