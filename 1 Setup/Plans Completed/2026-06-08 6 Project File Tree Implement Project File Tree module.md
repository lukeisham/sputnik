# Plan: Implement Module 6 — Project File Tree

**Created:** 2026-06-08  
**Module:** 6 Project File Tree  
**Build order position:** 4th (Foundation → Text Editor → Terminal → **Project File Tree** → Markdown Preview → PDF Viewer → HTML Preview → Resources)  
**Prerequisite modules completed:** Foundation (2), Text Editor (3), Terminal (7) ✅  

---

## Summary

Create 6 source files in `6 Project File Tree/` implementing the Project File Tree panel — a Finder-style folder browser in the left layout slot. The panel displays a recursive file hierarchy, supports file operations (create, rename, delete, copy path, reveal in Finder) via a right-click context menu, double-click to open files via `InterPanelRouter`, drag-and-drop in/out of the tree, and reacts to external file-system changes through `NSFilePresenter`.

---

## Pre-flight Checks

### Foundation APIs available (verified)

| Need | Available? | API |
|---|---|---|
| Active workspace directory | ✅ | `AppState.activeWorkspaceDirectory: URL?` |
| Open a file → editor | ✅ | `InterPanelRouter.open(_ url: URL) async` |
| Sync directory change | ✅ | `InterPanelRouter.syncDirectory(_ url: URL)` |
| Error alert presentation | ✅ | `SputnikAlert` (`.fileReadFailed`, `.fileWriteFailed`, `.custom`) |
| Debounce timer | ✅ | `DebounceTimer` (module 2.7) |
| Colour / spacing / font tokens | ✅ | `SputnikColor`, `SputnikSpacing`, `SputnikFont` |
| File type classification | ✅ | `FileType(url:)` |
| Panel layout slot | ✅ | `PanelID.fileTree` assigned to `.left` slot by default |
| `SputnikError` (thrown) | ✅ | `.hardwareAccessDenied`, `.processLaunchFailed`, `.ptyWriteFailed` — may need a new case for file-operation errors |

### Guide accuracy note
- The guide references `AppState.activeDirectory` but the actual property is `AppState.activeWorkspaceDirectory` — code will use the real property name.

### Issues to log
- None found. The guide is internally consistent and all referenced Foundation APIs exist.

---

## Files to Create

### 1. `6 Project File Tree/FileTreeNode.swift`

**Responsibility:** Data model for a single node in the file tree.

```swift
/// A single file or folder in the project tree.
/// Conforms to `Sendable` for safe background-task transfer (SW-1).
struct FileTreeNode: Identifiable, Sendable {
    let id: URL               // file URL (stable identity)
    let name: String          // display name (lastPathComponent)
    let isDirectory: Bool
    var children: [FileTreeNode]?  // nil = unexpanded; [] = empty folder
    let fileType: FileType
    let modificationDate: Date?
    let isReadable: Bool      // false when permission denied → lock icon
}
```

**Computed properties:**
- `icon`: SF Symbol name based on `isDirectory` + `fileType` (e.g. `"folder"`, `"doc.plaintext"`, `"doc.richtext"` for markdown, `"chevron.left.slash.chevron.right"` for HTML, `"doc.text.image"` for ASCII, `"lock.doc"` for unreadable, etc.)

**Conforms to:** `Identifiable` (via `id: URL`), `Sendable`, `Hashable`, `Equatable`

---

### 2. `6 Project File Tree/FileTreeViewModel.swift`

**Responsibility:** `@Observable` `@MainActor` class that owns the file tree state and coordinates scanning, selection, search filtering, and file operations.

**Owned state:**
- `rootNode: FileTreeNode?` — the root of the visible tree
- `activeDirectory: URL?` — mirrors `AppState.activeWorkspaceDirectory`
- `expandedNodeIDs: Set<URL>` — which folders are expanded
- `selectedNodeID: URL?` — the currently selected node
- `searchText: String` — filter text (empty = show all)
- `isScanning: Bool` — loading indicator
- `errorMessage: String?` — non-nil when directory is unavailable
- `displayedChildren(for:)` — returns filtered/sorted children of a node

**Methods:**
- `func selectRootDirectory(_ url: URL) async` — sets `activeDirectory`, kicks off initial scan on background `Task(priority: .userInitiated)`, calls `InterPanelRouter.syncDirectory(url)`
- `func refreshTree() async` — re-scans the active directory from disk (single source of truth), preserving expanded/selection state where possible
- `func scanDirectory(_ url: URL) async -> [FileTreeNode]` — uses `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)` on background `Task(priority: .userInitiated)`; returns sorted nodes (folders first, then files, each alphabetically)
- `func expandNode(_ id: URL) async` — lazy-loads children for a folder on background `Task(priority: .background)`, marks it expanded
- `func collapseNode(_ id: URL)` — removes from expanded set
- `func openNode(_ id: URL)` — if file → calls `InterPanelRouter.open(url)`; if folder → toggles expand/collapse
- `func createFile(named:in:)`, `func createFolder(named:in:)`, `func rename(node:to:)`, `func trash(node:)` — file operations via `FileManager`, refresh affected subtree on success, show `SputnikAlert` on failure
- `func revealedNodeIDs` — computed: returns the visible node IDs based on expanded set + search filter

**Threading (MR-3, SW-1):**
- All view mutations on `@MainActor`
- `scanDirectory` → background `Task(priority: .userInitiated)` → merge result on `@MainActor`
- `expandNode` (lazy-load) → background `Task(priority: .background)` → merge on `@MainActor`

**Dependency injection:**
- References `AppState` and `InterPanelRouter` via `@Environment` in the view layer, or passed via initializer. (Guide says it depends on Foundation 2.2 and 2.1 — passing them explicitly keeps the ViewModel testable.)

---

### 3. `6 Project File Tree/FileTreeRowView.swift`

**Responsibility:** A single row in the file tree — icon + name + optional status dot.

**Appearance:**
- SF Symbol icon from `FileTreeNode.icon`
- File/folder name in `SputnikColor.primaryText`, `SputnikFont.body`
- Indentation based on depth level
- Disclosure triangle for expandable folders (SwiftUI `DisclosureGroup` or manual chevron)
- Right-click triggers `FileContextMenu`
- Double-click calls `viewModel.openNode(node.id)`

---

### 4. `6 Project File Tree/FileContextMenu.swift`

**Responsibility:** Builds the right-click context menu for a tree node.

**Menu items (matching the guide's diagram):**
1. **New File** — prompts for name via inline text field or `NSAlert` with text input; creates via `FileManager`
2. **New Folder** — same pattern
3. **Divider**
4. **Rename** — inline rename (SwiftUI `TextField` in the row) or system rename dialog
5. **Move to Trash** — `FileManager.trashItem(at:resultingItemURL:)` or `NSWorkspace.shared.recycle([url])`
6. **Divider**
7. **Copy Path** — copies absolute path to `NSPasteboard.general`
8. **Divider**
9. **Reveal in Finder** — `NSWorkspace.shared.activateFileViewerSelecting([url])`

**Note:** "New File" and "New Folder" only appear when right-clicking a folder node or empty area. "Rename", "Move to Trash", "Copy Path", "Reveal in Finder" appear for all nodes.

---

### 5. `6 Project File Tree/FileTreePanel.swift`

**Responsibility:** Top-level SwiftUI view that assembles header, search bar, tree list, context menu, and drag-drop.

**Layout (matching guide's diagram):**
```
┌─────────────────────────────────────────┐
│  FILE TREE HEADER                       │
│  [📂 folder_name]           [🔍] [⋯]   │
│  ─────────────────────────────────────── │
│  Tree List (ScrollView + OutlineGroup)  │
└─────────────────────────────────────────┘
```

**Sub-components:**
- **Header:** Shows active directory name + "Select Folder" button (opens `NSOpenPanel` for directory selection) + search toggle button + overflow menu button
- **Search bar:** `TextField` bound to `viewModel.searchText`, filters visible nodes
- **Tree list:** Uses SwiftUI `List` with `OutlineGroup` (or recursive `DisclosureGroup`) driven by `viewModel.rootNode` and `viewModel.expandedNodeIDs`
- **Drag from tree:** `.onDrag` → `NSItemProvider` with file URL
- **Drop onto tree:** `.onDrop(of: [.fileURL])` → copies/moves dropped files into the target directory → refreshes tree
- **Empty state:** When no directory is selected → centered "Open a folder to get started" placeholder with a "Choose Folder…" button
- **Error state:** When directory is unavailable → "Directory unavailable" message with "Select Different Folder" button

**Dependencies:** `@Environment(AppState.self)`, `@Environment(InterPanelRouter.self)` (or a router environment object)

---

### 6. `6 Project File Tree/FileSystemWatcher.swift`

**Responsibility:** `NSObject` adopting `NSFilePresenter` to detect external changes (files added/deleted/renamed by Finder or another app) and notify the ViewModel.

```swift
final class FileSystemWatcher: NSObject, NSFilePresenter, Sendable {
    // NSFilePresenter requirements
    var presentedItemURL: URL?
    var presentedItemOperationQueue: OperationQueue  // .main
    
    func presentedSubitemDidChange(at url: URL)       // file added/deleted in watched dir
    func presentedItemDidChange()                     // the watched dir itself changed
    func accommodatePresentedItemDeletion(...)         // dir deleted → notify VM
    
    // Publishes changes via AsyncStream<URL> or a callback
    let changeStream: AsyncStream<URL>
}
```

The ViewModel subscribes to `changeStream`, debounces (300ms via `DebounceTimer`), then calls `refreshTree()`.

**Threading:** `NSFilePresenter` callbacks arrive on an arbitrary queue → events forwarded to `@MainActor` via `AsyncStream` continuation or `MainActor.run`.

---

## Implementation Order

1. **`FileTreeNode.swift`** — pure data, no dependencies
2. **`FileSystemWatcher.swift`** — depends only on Foundation
3. **`FileTreeViewModel.swift`** — depends on `FileTreeNode`, Foundation APIs
4. **`FileContextMenu.swift`** — depends on `FileTreeViewModel`
5. **`FileTreeRowView.swift`** — depends on `FileTreeNode`, `FileContextMenu`
6. **`FileTreePanel.swift`** — depends on all above, assembles final UI

---

## Integration Points

| Point | Foundation API | Usage |
|---|---|---|
| Directory selection | `AppState.activeWorkspaceDirectory` | Read on appear; write via `InterPanelRouter.syncDirectory()` |
| File open | `InterPanelRouter.open(_:)` | Double-click a file → router opens in editor |
| Error alerts | `SputnikAlert.custom(title:message:)` | File operation failures |
| Colour/spacing | `SputnikColor`, `SputnikSpacing`, `SputnikFont` | All UI styling |
| File type icons | `FileType` | Per-node SF Symbol selection |
| Debounce | `DebounceTimer` | External change → 300ms debounce → refresh |

---

## Coding Rule Compliance Checklist

- [ ] **SR-1:** Only communicates through Foundation (AppState, InterPanelRouter, SputnikAlert, design tokens)
- [ ] **SR-2:** No force-unwraps; all `FileManager` calls wrapped in `do/catch`; permission-denied paths handled gracefully
- [ ] **SR-3:** Children loaded lazily on folder expansion; no full recursive scan of large directories upfront
- [ ] **SR-4:** Directory scanning on background `Task`; UI updates on `@MainActor`
- [ ] **SR-5:** Uses `FileManager`, `NSFilePresenter`, `NSWorkspace`, `NSOpenPanel` — all Apple frameworks
- [ ] **SR-6:** One responsibility per file — 6 files as listed above
- [ ] **SW-1:** `async/await`, `Task`, `AsyncStream`; `@MainActor` on ViewModel and Views; `FileTreeNode` is `Sendable`
- [ ] **SW-2:** `[weak self]` in escaping closures (FileSystemWatcher stream, file-operation Tasks)
- [ ] **SW-3:** SwiftUI `List`/`OutlineGroup` with `.onDrag`/`.onDrop` modifiers; no `NSOutlineView` unless profiling shows it's needed
- [ ] **SW-4:** Doc comments on all public types and methods
- [ ] **MR-2:** `FileManager` for operations, `NSFilePresenter` for external sync
- [ ] **MR-3:** `.userInitiated` for user-triggered scan, `.background` for lazy folder expansion

---

## After Implementation

1. Verify the module compiles cleanly
2. Verify the panel integrates into the main `ContentView` / `AppOverview` layout (the file tree occupies `PanelPosition.left` by default)
3. Manually test: open a folder, expand/collapse, double-click to open files, right-click context menu, drag-drop, external file changes
4. Update the Module Guide: `status: draft` → `status: complete`, update `last_updated`
5. Move this plan to `Plans Completed/`
