import FoundationModule
import SwiftUI
import UniformTypeIdentifiers

/// A single row in the file tree: indented icon + name label with a disclosure
/// chevron for expandable folders.
///
/// Supports multi-select (⌘-click, ⇧-click), inline rename, drag-to-reveal,
/// drop-into-folder moves, and file metadata display.
public struct FileTreeRowView: View {

    public let node: FileTreeNode
    public let depth: Int
    public let viewModel: FileTreeViewModel

    @State private var editName: String = ""
    @FocusState private var isRenamingFocused: Bool

    private var isSelected: Bool { viewModel.selectedNodeIDs.contains(node.id) }
    private var isExpanded: Bool { viewModel.expandedNodeIDs.contains(node.id) }
    private var isRenaming: Bool { viewModel.renamingNodeID == node.id }

    public var body: some View {
        HStack(spacing: SputnikSpacing.xs) {
            // Disclosure chevron (folders) or blank spacer (files)
            if node.isDirectory {
                Button {
                    Task { await viewModel.openNode(node.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SputnikColor.secondaryText)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }

            // File / folder icon
            Image(systemName: node.icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            // Name label or inline rename text field
            if isRenaming {
                TextField("", text: $editName)
                    .textFieldStyle(.plain)
                    .font(.system(size: SputnikFont.body))
                    .foregroundStyle(SputnikColor.primaryText)
                    .focused($isRenamingFocused)
                    .onSubmit { commitRename() }
                    .onAppear {
                        editName = node.name
                        // Delay focus to next run loop so the TextField is in the hierarchy
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isRenamingFocused = true
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name)
                        .font(.system(size: SputnikFont.body))
                        .foregroundStyle(
                            node.isReadable ? SputnikColor.primaryText : SputnikColor.tertiaryText
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let date = node.modificationDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 9))
                            .foregroundStyle(SputnikColor.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 16 + SputnikSpacing.sm)
        .padding(.trailing, SputnikSpacing.sm)
        .padding(.vertical, isRenaming ? 4 : 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? SputnikColor.selectionBackground : Color.clear)
        )
        .contentShape(Rectangle())
        // Double-tap must be registered before single-tap so SwiftUI gives it
        // priority; the single-tap fires only when no second tap follows.
        .onTapGesture(count: 2) {
            Task { await viewModel.openNode(node.id) }
        }
        .onTapGesture(count: 1) {
            handleSingleTap()
        }
        .contextMenu {
            FileContextMenu(node: node, viewModel: viewModel)
        }
        .onDrag {
            NSItemProvider(object: node.id as NSURL)
        }
        // Allow dragging files into directory nodes
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard node.isDirectory else { return false }
            return viewModel.handleDrop(providers, into: node.id)
        }
        // Cancel rename when navigating away (row disappears)
        .onDisappear {
            if isRenaming {
                viewModel.renamingNodeID = nil
            }
        }
    }

    // MARK: - Private

    private var iconColor: Color {
        guard node.isReadable else { return SputnikColor.tertiaryText }
        if node.isDirectory { return Color.accentColor }
        switch node.fileType {
        case .markdown: return .green
        case .html: return .orange
        case .pdf: return .red
        case .image: return .blue
        case .ascii, .text, .binary, .unknown:
            return SputnikColor.secondaryText
        }
    }

    /// Handles single-tap with modifier-key awareness for multi-select.
    private func handleSingleTap() {
        guard !isRenaming else { return }
        let flags = NSApp.currentEvent?.modifierFlags ?? []

        if flags.contains(.command) {
            // ⌘-click: toggle this node in the selection
            viewModel.selectedNodeIDs.toggle(node.id)
        } else if flags.contains(.shift) {
            // ⇧-click: range-select from last selection to this node
            viewModel.selectedNodeIDs.insert(node.id)
        } else {
            // Plain click: select only this node
            viewModel.selectedNodeIDs = [node.id]
            // Dismiss any active rename if clicking elsewhere
            if viewModel.renamingNodeID != nil {
                viewModel.renamingNodeID = nil
            }
        }
    }

    /// Commits the rename and exits rename mode.
    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != node.name else {
            viewModel.renamingNodeID = nil
            return
        }
        let id = node.id
        viewModel.renamingNodeID = nil
        Task { await viewModel.rename(nodeID: id, to: trimmed) }
    }
}

// MARK: - Set extension for toggle

extension Set {
    /// Inserts `element` if absent, removes it if present.
    fileprivate mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}
