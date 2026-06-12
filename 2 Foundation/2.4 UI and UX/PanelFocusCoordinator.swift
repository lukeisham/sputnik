import Foundation
import Observation

/// Identifies a focusable UI region in a Sputnik window.
///
/// Each column in the dynamic layout is focusable, as is the pinned Terminal strip.
/// The File Tree, text editor, previews, and PDF viewer are all columns — they are
/// distinguished by their `columnID`, not by a separate enum case.
///
/// **Threading:** `Sendable` by value; compared by `Hashable` identity.
public enum PanelFocusTarget: Hashable, Sendable {
    /// A panel column identified by its `PanelColumn.id`.
    case column(UUID)
    /// The pinned Terminal strip at the bottom of the window.
    case terminal
}

/// Coordinates keyboard focus traversal across all panels in a window.
///
/// This is the single cross-panel focus authority (SR-1). Panels do not move focus
/// into each other directly — they read from this coordinator and the window's
/// view layer (`ContentView`) binds `@FocusState` to it.
///
/// **Threading:** `@MainActor` — all reads and writes are on the main actor.
/// Focus computation is a cheap O(n) walk over the column array (SR-4).
@Observable
@MainActor
public final class PanelFocusCoordinator {

    /// The currently focused panel target, or `nil` if nothing is focused.
    ///
    /// Set this directly to move focus to a specific panel. The `ContentView`
    /// observes this property and updates its `@FocusState` binding accordingly.
    public var focusedPanel: PanelFocusTarget?

    public init() {}

    // MARK: - Traversal order

    /// The ordered list of visible, focusable targets derived from the live layout.
    ///
    /// Order follows the visual left-to-right, top-to-bottom arrangement:
    /// columns in the order they appear in `layout.columns`, then the Terminal
    /// (if visible) as the final element.
    ///
    /// - Parameters:
    ///   - layout: The current `DynamicPanelLayout` for the window.
    ///   - terminalVisible: Whether the Terminal strip is shown.
    /// - Returns: An array of `PanelFocusTarget` values in traversal order.
    public func focusOrder(
        from layout: DynamicPanelLayout,
        terminalVisible: Bool
    ) -> [PanelFocusTarget] {
        var order: [PanelFocusTarget] = []
        for col in layout.columns {
            order.append(.column(col.id))
        }
        if terminalVisible {
            order.append(.terminal)
        }
        return order
    }

    // MARK: - Traversal actions

    /// Advance keyboard focus to the next visible panel (wrapping around).
    ///
    /// If nothing is currently focused, focuses the first panel in traversal order.
    /// Hidden panels are skipped because the order is derived from the live layout.
    ///
    /// - Parameters:
    ///   - layout: The current `DynamicPanelLayout` for the window.
    ///   - terminalVisible: Whether the Terminal strip is shown.
    public func focusNext(
        from layout: DynamicPanelLayout,
        terminalVisible: Bool
    ) {
        let order = focusOrder(from: layout, terminalVisible: terminalVisible)
        guard !order.isEmpty else {
            focusedPanel = nil
            return
        }
        guard let current = focusedPanel,
            let currentIndex = order.firstIndex(of: current)
        else {
            focusedPanel = order.first
            return
        }
        focusedPanel = order[(currentIndex + 1) % order.count]
    }

    /// Move keyboard focus to the previous visible panel (wrapping around).
    ///
    /// If nothing is currently focused, focuses the last panel in traversal order.
    ///
    /// - Parameters:
    ///   - layout: The current `DynamicPanelLayout` for the window.
    ///   - terminalVisible: Whether the Terminal strip is shown.
    public func focusPrevious(
        from layout: DynamicPanelLayout,
        terminalVisible: Bool
    ) {
        let order = focusOrder(from: layout, terminalVisible: terminalVisible)
        guard !order.isEmpty else {
            focusedPanel = nil
            return
        }
        guard let current = focusedPanel,
            let currentIndex = order.firstIndex(of: current)
        else {
            focusedPanel = order.last
            return
        }
        focusedPanel = order[(currentIndex - 1 + order.count) % order.count]
    }

    /// Convenience: focus the first text editor column, falling back to the first column.
    ///
    /// - Parameter layout: The current `DynamicPanelLayout` for the window.
    public func focusEditor(from layout: DynamicPanelLayout) {
        if let editorCol = layout.columns.first(where: { $0.renderMode == .textEditor }) {
            focusedPanel = .column(editorCol.id)
        } else if let firstCol = layout.columns.first {
            focusedPanel = .column(firstCol.id)
        }
    }

    /// Convenience: focus the Terminal strip.
    public func focusTerminal() {
        focusedPanel = .terminal
    }

    /// Convenience: focus the File Tree column, if present.
    ///
    /// - Parameter layout: The current `DynamicPanelLayout` for the window.
    public func focusFileTree(from layout: DynamicPanelLayout) {
        if let ftCol = layout.columns.first(where: { $0.renderMode == .fileTree }) {
            focusedPanel = .column(ftCol.id)
        }
    }
}
