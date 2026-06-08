import SwiftUI

/// A single row in the file tree: indented icon + name label with a disclosure
/// chevron for expandable folders.
///
/// Single tap selects the node; double-tap opens a file or toggles a folder.
/// The disclosure chevron triggers expand/collapse independently of the row tap.
public struct FileTreeRowView: View {

    public let node: FileTreeNode
    public let depth: Int
    public let viewModel: FileTreeViewModel

    private var isSelected: Bool { viewModel.selectedNodeID == node.id }
    private var isExpanded: Bool { viewModel.expandedNodeIDs.contains(node.id) }

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

            // Name label
            Text(node.name)
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(node.isReadable ? SputnikColor.primaryText : SputnikColor.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 16 + SputnikSpacing.sm)
        .padding(.trailing, SputnikSpacing.sm)
        .padding(.vertical, 2)
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
            viewModel.selectedNodeID = node.id
        }
        .contextMenu {
            FileContextMenu(node: node, viewModel: viewModel)
        }
        .onDrag {
            NSItemProvider(object: node.id as NSURL)
        }
    }

    // MARK: - Private

    private var iconColor: Color {
        guard node.isReadable else { return SputnikColor.tertiaryText }
        if node.isDirectory { return Color.accentColor }
        switch node.fileType {
        case .markdown: return .green
        case .html:     return .orange
        case .pdf:      return .red
        case .ascii, .text, .binary, .unknown:
            return SputnikColor.secondaryText
        }
    }
}
