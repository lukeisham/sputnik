import FoundationModule
import SwiftUI
import UniformTypeIdentifiers

/// Drop delegate for dropping a column onto another column (creating a tab).
///
/// Decodes the source column UUID from the item provider, validates the File Tree
/// edge constraint, and calls `layout.moveColumn(id:to:)` to reposition the dragged
/// column so it becomes a tab in the target column.
struct ColumnDropDelegate: DropDelegate {

    @Binding var layout: DynamicPanelLayout
    let columnIndex: Int

    func validateDrop(info: DropInfo) -> Bool {
        guard !info.itemProviders(for: [UTType.plainText]).isEmpty else { return false }
        // Synchronous validation — we can't load the UUID synchronously from the provider,
        // so we return true and let the model-level guard in moveColumn reject invalid drops.
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.plainText]).first else { return false }

        item.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
            (data, error) in
            guard let data = data as? Data,
                let uuidString = String(data: data, encoding: .utf8),
                let sourceUUID = UUID(uuidString: uuidString)
            else { return }

            Task { @MainActor in
                // Move the dragged column to the target position
                layout.moveColumn(id: sourceUUID, to: columnIndex)
            }
        }
        return true
    }
}
