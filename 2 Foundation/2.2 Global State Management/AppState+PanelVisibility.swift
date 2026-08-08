import Foundation

extension AppState {

    // MARK: - Panel visibility (dynamic layout)

    /// Returns true if a column with the given render mode exists in the active window.
    public func hasColumn(renderMode: PanelID) -> Bool {
        activeWindow?.hasColumn(renderMode: renderMode) ?? false
    }

    /// Toggle a column by render mode: remove if present, add if absent.
    public func toggleColumn(renderMode: PanelID) {
        activeWindow?.toggleColumn(renderMode: renderMode)
    }

    public func toggleTerminal() {
        activeWindow?.toggleTerminal()
    }

    public func restoreDefaultLayout() {
        activeWindow?.restoreDefaultLayout()
    }

    /// Reconfigure the active window to a focused editor layout (text editor only).
    public func focusEditor() {
        activeWindow?.setDynamicLayout(
            DynamicPanelLayout(columns: [
                PanelColumn(renderMode: .fileTree, width: 0.20),
                PanelColumn(renderMode: .textEditor, width: 0.80),
            ]))
    }

    /// Reconfigure the active window to a focused reader layout (markdown preview only, no file tree).
    public func focusReader() {
        activeWindow?.setDynamicLayout(
            DynamicPanelLayout(columns: [
                PanelColumn(renderMode: .markdownPreview, width: 1.0)
            ]))
    }
}
