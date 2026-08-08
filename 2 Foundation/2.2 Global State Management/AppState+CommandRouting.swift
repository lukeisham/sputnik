import Foundation

extension AppState {

    // MARK: - Editor command handler (SR-1)

    /// Registers the editor command handler (called by EditorViewModel at init).
    public func registerEditorCommandHandler(_ handler: EditorCommandHandling) {
        editorCommandHandler = handler
    }
}
