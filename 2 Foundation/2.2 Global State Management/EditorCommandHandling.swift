import Foundation

/// Protocol for menu commands that the editor implements (Save, Save As, Render as HTML, ASCII Studio).
///
/// SR-1: Foundation calls methods on this protocol (registered in AppState) without
/// importing module 3. The editor registers itself at launch, keeping Foundation
/// an interface layer that does not know about TextEditorModule.
public protocol EditorCommandHandling: AnyObject {
    /// Saves the current buffer to the open file.
    func save() async throws

    /// Opens a Save As dialog and writes to the selected file.
    func saveAs(to newURL: URL) async throws

    /// Opens the HTML Preview panel with the current file.
    func renderAsHTML() async throws

    /// Presents the ASCII Studio for the active editor.
    func showASCIIStudio() async throws
}
