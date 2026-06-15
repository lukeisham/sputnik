import AppKit
import FoundationModule

/// Presents an `NSMenu` popup for interaction results:
/// - Fuzzy fallback pick list (ranked candidate sections)
/// - Per-slot alternates submenu (when a resource slot has multiple strong matches)
@MainActor
public enum InteractionPopupMenu {

    /// Presents a popup menu with the given items.
    /// - Parameters:
    ///   - title: The greyed, non-clickable title at the top of the menu.
    ///   - items: The selectable items to show.
    ///   - rect: The anchor rectangle for the popup (in `view`'s coordinates).
    ///   - view: The view to present the popup from.
    ///   - onSelect: Called when the user selects an item, with the chosen item.
    public static func present(
        title: String,
        items: [InteractionSectionItem],
        relativeTo rect: NSRect,
        in view: NSView,
        onSelect: @escaping (InteractionSectionItem) -> Void
    ) {
        let menu = NSMenu(title: title)

        // Greyed, non-clickable title.
        let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if items.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No relevant sections found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            menu.addItem(.separator())

            for item in items {
                let menuItem = ClosureMenuItem(title: item.sectionTitle) {
                    onSelect(item)
                }
                menuItem.toolTip = String(item.preview.prefix(80))
                menu.addItem(menuItem)
            }
        }

        menu.popUp(positioning: nil, at: rect.origin, in: view)
    }
}
