import AppKit
import FoundationModule
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Top-level SwiftUI view for the Project File Tree panel.
///
/// Assembles the header, search bar, recursive tree list, drag-and-drop, and
/// empty / error placeholder states. Occupies the `.left` slot in `ContentView`.
///
/// Dependencies are read from `@Environment` (SR-1):
/// - `WindowState` — per-window workspace directory, document opening
public struct FileTreePanel: View {

    @Environment(WindowState.self) private var windowState
    @State private var viewModel = FileTreeViewModel()
    @State private var showSearch: Bool = false

    private let router: any InterPanelRouter

    public init(router: any InterPanelRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if showSearch { searchBar }
            Divider()
            treeBody
        }
        .background(SputnikColor.secondaryBackground)
        .task {
            viewModel.configure(windowState: windowState, router: router)
            // Restore last workspace directory if already set
            if let dir = windowState.activeWorkspaceDirectory {
                await viewModel.selectRootDirectory(dir)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: SputnikSpacing.xs) {
            // Folder icon + current directory name (truncated)
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(SputnikColor.secondaryText)

            Text(viewModel.activeDirectory?.lastPathComponent ?? "No Folder")
                .font(.system(size: SputnikFont.body, weight: .medium))
                .foregroundStyle(SputnikColor.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            // Search toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSearch.toggle()
                    if !showSearch { viewModel.searchText = "" }
                }
            } label: {
                Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(showSearch ? SputnikColor.accent : SputnikColor.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Toggle Search")

            // Open-folder button
            Button {
                openFolderPanel()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13))
                    .foregroundStyle(SputnikColor.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Open Folder…")
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .padding(.vertical, SputnikSpacing.sm)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: SputnikSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(SputnikColor.tertiaryText)

            @Bindable var vm = viewModel
            TextField("Filter files…", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: SputnikFont.body))

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SputnikColor.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .padding(.vertical, SputnikSpacing.xs)
        .background(SputnikColor.background)
    }

    // MARK: - Tree body

    @ViewBuilder
    private var treeBody: some View {
        if viewModel.activeDirectory == nil {
            emptyState
        } else if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if viewModel.isScanning && viewModel.rootNode == nil {
            loadingState
        } else if let root = viewModel.rootNode {
            ScrollView {
                LazyVStack(spacing: 0) {
                    treeRows(for: root, depth: 0, isRoot: true)
                }
                .padding(.vertical, SputnikSpacing.xs)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { [viewModel] providers in
                guard let dir = viewModel.activeDirectory else { return false }
                return viewModel.handleDrop(providers, into: dir)
            }
            .onDeleteCommand {
                Task { await viewModel.trashSelected() }
            }
            .background {
                keyboardShortcutOverlay
            }
        } else {
            emptyState
        }
    }

    // MARK: - Keyboard shortcuts

    /// Hidden buttons that capture ⌘N, ⌘⇧N, and ⏎ (Enter) keyboard shortcuts.
    private var keyboardShortcutOverlay: some View {
        Group {
            // ⌘N — New file in active directory
            Button {
                guard let dir = viewModel.activeDirectory else { return }
                promptNewFile(in: dir)
            } label: {
                EmptyView()
            }
            .keyboardShortcut("n", modifiers: .command)
            .frame(width: 0, height: 0)

            // ⌘⇧N — New folder in active directory
            Button {
                guard let dir = viewModel.activeDirectory else { return }
                promptNewFolder(in: dir)
            } label: {
                EmptyView()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .frame(width: 0, height: 0)

            // ⏎ — Start inline rename on selected node
            Button {
                viewModel.beginRenameSelected()
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [])
            .frame(width: 0, height: 0)

            // ⌘C — Copy path of selected node(s) to clipboard
            Button {
                copySelectedPaths()
            } label: {
                EmptyView()
            }
            .keyboardShortcut("c", modifiers: .command)
            .frame(width: 0, height: 0)
        }
    }

    // MARK: - Clipboard operations

    private func copySelectedPaths() {
        let paths = viewModel.selectedNodeIDs.map(\.path).sorted()
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }

    // MARK: - File creation prompts

    private func promptNewFile(in directory: URL) {
        promptFile(title: "New File", message: "Enter a name for the new file:") { name in
            Task { await viewModel.createFile(named: name, in: directory) }
        }
    }

    private func promptNewFolder(in directory: URL) {
        promptFile(title: "New Folder", message: "Enter a name for the new folder:") { name in
            Task { await viewModel.createFolder(named: name, in: directory) }
        }
    }

    private func promptFile(title: String, message: String, onConfirm: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = ""
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onConfirm(name)
    }

    // MARK: - Recursive tree rows

    // AnyView is used here intentionally to break the recursive opaque-type inference
    // that would otherwise produce an infinite `some View` type (e.g. _ConditionalContent<…some View…>).
    private func treeRows(for node: FileTreeNode, depth: Int, isRoot: Bool) -> AnyView {
        if isRoot {
            let children = viewModel.displayedChildren(for: node)
            return AnyView(
                ForEach(children) { child in
                    self.treeRows(for: child, depth: depth, isRoot: false)
                }
            )
        } else {
            return AnyView(
                Group {
                    FileTreeRowView(node: node, depth: depth, viewModel: viewModel)

                    if node.isDirectory && viewModel.expandedNodeIDs.contains(node.id) {
                        let children = viewModel.displayedChildren(for: node)
                        ForEach(children) { child in
                            self.treeRows(for: child, depth: depth + 1, isRoot: false)
                        }
                    }
                }
            )
        }
    }

    // MARK: - Placeholder states

    private var emptyState: some View {
        VStack(spacing: SputnikSpacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(SputnikColor.tertiaryText)
            Text("Open a folder to get started")
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.secondaryText)
                .multilineTextAlignment(.center)
            Button("Choose Folder…") { openFolderPanel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(SputnikSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: SputnikSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Directory Unavailable")
                .font(.system(size: SputnikFont.body, weight: .semibold))
                .foregroundStyle(SputnikColor.primaryText)
            Text(message)
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.secondaryText)
                .multilineTextAlignment(.center)
            Button("Select Different Folder") { openFolderPanel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(SputnikSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: SputnikSpacing.sm) {
            ProgressView()
                .scaleEffect(0.75)
            Text("Loading…")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Folder picker

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a project folder to open in Sputnik"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.selectRootDirectory(url) }
    }

}
