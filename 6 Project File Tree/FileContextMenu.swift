import SwiftUI
import AppKit

/// Menu items for the file-tree right-click context menu.
///
/// Used as the content of `.contextMenu { FileContextMenu(node:viewModel:) }` on
/// each row. Name-input dialogs use `NSAlert` with a text field accessory so the
/// menu itself stays stateless.
public struct FileContextMenu: View {

    public let node: FileTreeNode
    public let viewModel: FileTreeViewModel

    public var body: some View {
        if node.isDirectory {
            Button("New File") { promptNewFile() }
            Button("New Folder") { promptNewFolder() }
            Divider()
        }

        Button("Rename") { promptRename() }
        Button("Move to Trash", role: .destructive) {
            Task { await viewModel.trash(nodeID: node.id) }
        }

        Divider()

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.id.path, forType: .string)
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([node.id])
        }
    }

    // MARK: - Private

    private func promptNewFile() {
        prompt(title: "New File", message: "Enter a name for the new file:") { name in
            Task { await viewModel.createFile(named: name, in: node.id) }
        }
    }

    private func promptNewFolder() {
        prompt(title: "New Folder", message: "Enter a name for the new folder:") { name in
            Task { await viewModel.createFolder(named: name, in: node.id) }
        }
    }

    private func promptRename() {
        prompt(title: "Rename", message: "Enter a new name:", defaultValue: node.name) { name in
            Task { await viewModel.rename(nodeID: node.id, to: name) }
        }
    }

    private func prompt(
        title: String,
        message: String,
        defaultValue: String = "",
        onConfirm: @escaping (String) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = defaultValue
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onConfirm(name)
    }
}
