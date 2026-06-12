import FoundationModule
import SwiftUI

/// A thin vertical divider between two adjacent panel columns.
///
/// Supports drag-to-resize: dragging horizontally shifts width between the
/// two neighbouring columns (left and right). The visual line is 1 pt; the
/// interactive hit area is the full 8 pt gap provided by the parent `ZStack`.
/// A haptic detent fires when the split crosses 50/50.
struct ResizeDivider: View {

    /// Index of the column to the left of this divider.
    let leftColumnIndex: Int
    @Binding var layout: DynamicPanelLayout
    /// Total pixel width available for all columns (GeometryReader size minus divider gaps).
    let totalAvailableWidth: CGFloat

    /// Tracks cumulative translation so we emit per-frame deltas to `layout.resize`.
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(SputnikColor.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())  // make the full 8 pt zone interactive
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let delta = value.translation.width - lastTranslation
                        lastTranslation = value.translation.width
                        layout.resize(
                            betweenLeftIndex: leftColumnIndex,
                            delta: delta,
                            totalAvailableWidth: totalAvailableWidth
                        )
                    }
                    .onEnded { _ in
                        lastTranslation = 0
                        // Haptic detent when the split is near 50/50.
                        if layout.isNearEvenSplit(leftIndex: leftColumnIndex) {
                            layout.snapToEvenSplit(leftIndex: leftColumnIndex)
                            NSHapticFeedbackManager.defaultPerformer.perform(
                                .alignment, performanceTime: .default)
                        }
                    }
            )
    }
}
