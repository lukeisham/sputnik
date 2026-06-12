import FoundationModule
import SwiftUI
import UniformTypeIdentifiers

/// An 8 pt wide invisible drop zone between two panel columns.
///
/// On hover (drag-enter) it highlights with an accent tint. On drop it creates a new
/// column with the dragged column's render mode at the insertion index, then clears
/// the drag-source dim via `draggingColumnID`.
struct DropZoneView: View {

    let insertionIndex: Int
    @Binding var layout: DynamicPanelLayout
    /// Cleared on successful drop to end the drag-source dim effect.
    @Binding var draggingColumnID: UUID?

    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? SputnikColor.accentPrimary.opacity(0.30) : Color.clear)
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.plainText],
                delegate: DropZoneDropDelegate(
                    insertionIndex: insertionIndex,
                    layout: $layout,
                    isHovering: $isHovering,
                    draggingColumnID: $draggingColumnID
                )
            )
    }
}

// MARK: - DropZone DropDelegate

/// Handles drops on a between-column drop zone.
private struct DropZoneDropDelegate: DropDelegate {

    let insertionIndex: Int
    @Binding var layout: DynamicPanelLayout
    @Binding var isHovering: Bool
    /// Cleared on successful drop to end the drag-source dim effect.
    @Binding var draggingColumnID: UUID?

    func dropEntered(info: DropInfo) {
        isHovering = true
    }

    func dropExited(info: DropInfo) {
        isHovering = false
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard info.itemProviders(for: [UTType.plainText]).first != nil else { return false }
        // We need to synchronously validate. The payload is a UUID string.
        // Since we can't read it synchronously from the provider, we return true
        // and let the layout's canInsert guard reject in performDrop.
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        isHovering = false
        guard let item = info.itemProviders(for: [UTType.plainText]).first else { return false }

        item.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
            (data, error) in
            guard let data = data as? Data,
                let uuidString = String(data: data, encoding: .utf8),
                let sourceUUID = UUID(uuidString: uuidString)
            else { return }

            Task { @MainActor in
                // Look up the source column's render mode
                guard let sourceColumn = layout.columns.first(where: { $0.id == sourceUUID })
                else { return }
                let renderMode = sourceColumn.renderMode
                guard layout.canInsert(renderMode: renderMode, at: insertionIndex) else { return }

                // Remove the source column first
                if let sourceIndex = layout.columns.firstIndex(where: { $0.id == sourceUUID }) {
                    var adjustedIndex = insertionIndex
                    if sourceIndex < insertionIndex { adjustedIndex -= 1 }
                    layout.moveColumn(id: sourceUUID, to: adjustedIndex)
                }
                // Clear drag feedback state
                draggingColumnID = nil
            }
        }
        return true
    }
}
