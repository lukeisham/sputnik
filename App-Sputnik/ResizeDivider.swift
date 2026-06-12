import FoundationModule
import SwiftUI

/// A thin vertical divider between columns.
///
/// Drag-resize interaction is added in Part 3. For now this is a static separator
/// that fills the column gap.
struct ResizeDivider: View {
    var body: some View {
        Rectangle()
            .fill(SputnikColor.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}
