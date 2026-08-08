import AppKit
import Foundation

extension AppState {

    // MARK: - Recent files

    public func noteRecentFile(_ url: URL) {
        var list = layout.recentFiles
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        if list.count > LayoutState.maxRecentFiles {
            list.removeLast(list.count - LayoutState.maxRecentFiles)
        }
        layout.recentFiles = list
    }

    public func clearRecentFiles() {
        layout.recentFiles.removeAll()
    }

    // MARK: - Document lifecycle (delegates to active window + updates recent files)

    @discardableResult
    public func openDocument(url: URL) -> DocumentSession {
        guard let win = activeWindow else {
            let w = createWindow()
            return w.openDocument(url: url)
        }
        let session = win.openDocument(url: url)
        noteRecentFile(url)
        return session
    }

    @discardableResult
    public func newUntitledDocument() -> DocumentSession {
        guard let win = activeWindow else {
            let w = createWindow()
            return w.newUntitledDocument()
        }
        return win.newUntitledDocument()
    }

    public func closeDocument(_ id: UUID) {
        activeWindow?.closeDocument(id)
    }

    /// Creates a new untitled document with the given file type and activates it.
    @discardableResult
    public func newTypedDocument(fileType: FileType) -> DocumentSession {
        let session = newUntitledDocument()
        session.fileType = fileType
        return session
    }

    /// Prompts the user for a folder name and creates it inside the active workspace directory.
    /// Silently returns when no workspace directory is open.
    public func newFolder() {
        guard let workspace = activeWorkspaceDirectory else { return }

        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter a name for the new folder:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.placeholderString = "untitled folder"
        alert.accessoryView = textField
        textField.becomeFirstResponder()

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { return }

        let target = workspace.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }

    /// Reorders documents in the active window. Delegates to `WindowState.moveDocument(fromOffsets:toOffset:)`.
    public func moveDocument(fromOffsets: IndexSet, toOffset: Int) {
        activeWindow?.moveDocument(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}
