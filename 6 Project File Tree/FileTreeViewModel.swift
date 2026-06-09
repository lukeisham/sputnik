import Foundation
import Observation
import AppKit

/// Manages the file tree state: directory scanning, node expansion, selection,
/// search filtering, and file-system operations.
///
/// All mutations run on `@MainActor`. Directory scanning is off-loaded to
/// background `Task`s via the static `loadLevel(_:)` helper; results are merged
/// back on `@MainActor` (MR-3, SW-1, SW-4).
@Observable
@MainActor
public final class FileTreeViewModel {

    // MARK: - Observable state

    public private(set) var rootNode: FileTreeNode?
    public private(set) var activeDirectory: URL?
    public var expandedNodeIDs: Set<URL> = []
    public var selectedNodeID: URL?
    public var searchText: String = ""
    public private(set) var isScanning: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Dependencies (wired after init via configure)

    private weak var windowState: WindowState?

    // MARK: - Internals

    private var watcher: FileSystemWatcher?
    private let debounce = DebounceTimer()
    private var watchTask: Task<Void, Never>?

    // MARK: - Init

    public init() {}

    // MARK: - Configuration

    /// Wires up the per-window `WindowState`. Called once from `FileTreePanel.task`.
    public func configure(windowState: WindowState) {
        self.windowState = windowState
    }

    // MARK: - Directory selection

    /// Selects a new root directory, scans it, starts watching for changes, and
    /// updates `windowState.activeWorkspaceDirectory` so the terminal can follow.
    public func selectRootDirectory(_ url: URL) async {
        guard activeDirectory != url else { return }
        activeDirectory = url
        errorMessage = nil
        expandedNodeIDs = []
        selectedNodeID = nil
        windowState?.activeWorkspaceDirectory = url
        await refreshTree()
        startWatching(url)
    }

    // MARK: - Refresh

    /// Re-scans the active directory from disk, preserving expanded/selection state.
    public func refreshTree() async {
        guard let dir = activeDirectory else { return }
        isScanning = true
        defer { isScanning = false }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            errorMessage = "The folder "\(dir.lastPathComponent)" no longer exists or is unavailable."
            return
        }

        let scanned = await scanLevel(dir)
        rootNode = FileTreeNode(
            id: dir,
            name: dir.lastPathComponent,
            isDirectory: true,
            children: scanned,
            fileType: .unknown,
            modificationDate: nil,
            isReadable: true
        )
        errorMessage = nil
    }

    // MARK: - Expand / Collapse

    /// Lazy-loads children for a folder on a background task and marks it expanded.
    public func expandNode(_ id: URL) async {
        expandedNodeIDs.insert(id)
        guard needsLoad(id) else { return }
        let children = await Task(priority: .background) { FileTreeViewModel.loadLevel(id) }.value
        applyChildren(children, toNodeID: id, in: &rootNode)
    }

    /// Removes a folder from the expanded set.
    public func collapseNode(_ id: URL) {
        expandedNodeIDs.remove(id)
    }

    // MARK: - Node interaction

    /// For a directory: toggles expand/collapse. For a file: opens it via `WindowState`.
    public func openNode(_ id: URL) async {
        guard let node = findNode(id, in: rootNode) else { return }
        if node.isDirectory {
            if expandedNodeIDs.contains(id) {
                collapseNode(id)
            } else {
                await expandNode(id)
            }
        } else {
            windowState?.openDocument(url: id)
        }
    }

    // MARK: - File operations

    /// Creates an empty file with the given name inside `directory`.
    public func createFile(named name: String, in directory: URL) async {
        let dest = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            showAlert(title: "File Already Exists",
                      message: "A file named "\(name)" already exists in this folder.")
            return
        }
        let created = FileManager.default.createFile(atPath: dest.path, contents: nil)
        if !created {
            showAlert(title: "Could Not Create File",
                      message: "The file "\(name)" could not be created.")
        }
        await refreshTree()
    }

    /// Creates a new folder with the given name inside `directory`.
    public func createFolder(named name: String, in directory: URL) async {
        let dest = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
            await refreshTree()
        } catch {
            showAlert(title: "Could Not Create Folder", message: error.localizedDescription)
        }
    }

    /// Renames the node at `nodeID` to `newName`.
    public func rename(nodeID: URL, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dest = nodeID.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(at: nodeID, to: dest)
            if selectedNodeID == nodeID { selectedNodeID = dest }
            await refreshTree()
        } catch {
            showAlert(title: "Could Not Rename", message: error.localizedDescription)
        }
    }

    /// Moves the node at `nodeID` to the system Trash.
    public func trash(nodeID: URL) async {
        do {
            try FileManager.default.trashItem(at: nodeID, resultingItemURL: nil)
            if selectedNodeID == nodeID { selectedNodeID = nil }
            await refreshTree()
        } catch {
            showAlert(title: "Could Not Move to Trash", message: error.localizedDescription)
        }
    }

    // MARK: - Search / filtering

    /// Returns filtered, sorted children of `node` based on `searchText`.
    public func displayedChildren(for node: FileTreeNode) -> [FileTreeNode] {
        guard let children = node.children else { return [] }
        guard !searchText.isEmpty else { return children }
        return children.filter { child in
            child.name.localizedCaseInsensitiveContains(searchText)
                || (child.isDirectory && hasMatchingDescendant(child))
        }
    }

    // MARK: - Private: scanning

    private func scanLevel(_ url: URL) async -> [FileTreeNode] {
        await Task(priority: .userInitiated) { FileTreeViewModel.loadLevel(url) }.value
    }

    /// Non-isolated helper invoked from background `Task`s; never captures `self`.
    private static func loadLevel(_ url: URL) -> [FileTreeNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isReadableKey]
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            return contents.compactMap { itemURL -> FileTreeNode? in
                guard let rv = try? itemURL.resourceValues(forKeys: Set(keys)) else { return nil }
                let isDir = rv.isDirectory ?? false
                return FileTreeNode(
                    id: itemURL,
                    name: itemURL.lastPathComponent,
                    isDirectory: isDir,
                    children: nil,
                    fileType: isDir ? .unknown : FileType(url: itemURL),
                    modificationDate: rv.contentModificationDate,
                    isReadable: rv.isReadable ?? false
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            return []
        }
    }

    // MARK: - Private: file watching

    private func startWatching(_ url: URL) {
        watchTask?.cancel()
        watcher?.stop()
        let newWatcher = FileSystemWatcher(url: url)
        watcher = newWatcher
        watchTask = Task { [weak self] in
            for await _ in newWatcher.changeStream {
                guard let self else { break }
                self.debounce.schedule(delay: 0.3) {
                    Task { @MainActor [weak self] in
                        await self?.refreshTree()
                    }
                }
            }
        }
    }

    // MARK: - Private: tree helpers

    private func needsLoad(_ id: URL) -> Bool {
        findNode(id, in: rootNode)?.children == nil
    }

    private func findNode(_ id: URL, in node: FileTreeNode?) -> FileTreeNode? {
        guard let node else { return nil }
        if node.id == id { return node }
        for child in node.children ?? [] {
            if let found = findNode(id, in: child) { return found }
        }
        return nil
    }

    private func applyChildren(_ children: [FileTreeNode], toNodeID id: URL, in node: inout FileTreeNode?) {
        guard var n = node else { return }
        if n.id == id {
            n.children = children
            node = n
            return
        }
        if var kids = n.children {
            for i in kids.indices {
                applyChildren(children, toNodeID: id, in: &kids[i])
            }
            n.children = kids
            node = n
        }
    }

    private func hasMatchingDescendant(_ node: FileTreeNode) -> Bool {
        for child in node.children ?? [] {
            if child.name.localizedCaseInsensitiveContains(searchText) { return true }
            if child.isDirectory && hasMatchingDescendant(child) { return true }
        }
        return false
    }

    // MARK: - Private: alert

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
