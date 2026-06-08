import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Top-level SwiftUI view for the Project File Tree panel.
///
/// Assembles the header, search bar, recursive tree list, drag-and-drop, and
/// empty / error placeholder states. Occupies the `.left` slot in `ContentView`.
///
/// Dependencies are read from `@Environment` (SR-1):
/// - `AppState` — workspace directory, document opening
public struct FileTreePanel: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = FileTreeViewModel()
    @State private var showSearch: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            if showSearch { searchBar }
            Divider()
            treeBody
        }
        .background(SputnikColor.secondaryBackground)
        .task {
            viewModel.configure(appState: appState)
            // Restore last workspace directory if already set
            if let dir = appState.activeWorkspaceDirectory {
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
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                handleDrop(providers, into: viewModel.activeDirectory)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Recursive tree rows

    @ViewBuilder
    private func treeRows(for node: FileTreeNode, depth: Int, isRoot: Bool) -> some View {
        // Skip rendering the root node itself; show its children directly
        if isRoot {
            let children = viewModel.displayedChildren(for: node)
            ForEach(children) { child in
                treeRows(for: child, depth: depth, isRoot: false)
            }
        } else {
            FileTreeRowView(node: node, depth: depth, viewModel: viewModel)

            if node.isDirectory && viewModel.expandedNodeIDs.contains(node.id) {
                let children = viewModel.displayedChildren(for: node)
                ForEach(children) { child in
                    treeRows(for: child, depth: depth + 1, isRoot: false)
                }
            }
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

    // MARK: - Drop handling

    /// Accepts dropped file URLs and copies them into `directory`.
    ///
    /// `URL` does not conform to `NSItemProviderReading`, so we use the lower-level
    /// `loadItem(forTypeIdentifier:)` API and coerce the result to a URL manually.
    private func handleDrop(_ providers: [NSItemProvider], into directory: URL?) -> Bool {
        guard let directory else { return false }
        let typeID = UTType.fileURL.identifier
        var handled = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(typeID) else { continue }
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                guard let url else { return }
                let dest = directory.appendingPathComponent(url.lastPathComponent)
                Task { @MainActor in
                    do {
                        try FileManager.default.copyItem(at: url, to: dest)
                        await viewModel.refreshTree()
                    } catch {
                        // Silently ignore — drop rejected (standard macOS behaviour)
                    }
                }
            }
            handled = true
        }
        return handled
    }
}
