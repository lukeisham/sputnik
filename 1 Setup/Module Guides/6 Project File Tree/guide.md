---
module: 6 Project File Tree
status: active
last_updated: 2026-06-15
last_verified: 2026-06-15
plan: 1 Setup/Plans Completed/2026-06-12 File Tree quality-of-life features.md
---

## Purpose

The Project File Tree lets the user browse a local folder's hierarchy, open files into the active editor tab, and perform file-system operations (create, rename, delete, drag) — functioning as Sputnik's Finder-style navigation panel in the left slot.

## Diagram

```
PROJECT FILE TREE PANEL  (occupies the left slot; see module 2.0 overview)
────────────────────────────────────────────────────────────────────────────

 ┌─────────────────────────────────────────────────────────────────────────┐
 │  FILE TREE HEADER                                                       │
 │  [📂 App_Sputnik]                                          [🔍] [⋯]   │
 │  ───────────────────────────────────────────────────────────────────     │
 │                                                                          │
 │  📁 App_Sputnik/                                                         │
 │  ├── 📁 2 Foundation/                                                    │
 │  │   ├── 📄 AppDelegate.swift                                            │
 │  │   ├── 📄 ContentView.swift                                            │
 │  │   └── 📁 Utilities/                                                   │
 │  │       └── 📄 FileHelpers.swift                                        │
 │  ├── 📁 3 Editor Window/                                                 │
 │  │   ├── 📝 guide.md                                                     │
 │  │   └── 📁 src/                                                         │
 │  │       └── 🔤 Lexer.swift                                              │
 │  ├── 📕 spec.pdf                                                         │
 │  ├── 📁 7 Terminal/                                                      │
 │  │   └── 📄 PTYManager.swift                                             │
 │  └── 🌐 index.html                                                       │
 │                                                                          │
 │  ───────────────────────────────────────────────────────────────────     │
 │                                                                          │
 │  RIGHT-CLICK CONTEXT MENU  (on a file or folder)                         │
 │  ┌─────────────────────────┐                                             │
 │  │ 📄 New File             │                                             │
 │  │ 📂 New Folder           │                                             │
 │  │ ─────────────────────── │                                             │
 │  │ ✏️  Rename              │                                             │
 │  │ 🗑️  Move to Trash       │                                             │
 │  │ ─────────────────────── │                                             │
 │  │ 📋 Copy Path            │                                             │
 │  │ ─────────────────────── │                                             │
 │  │ 📂 Reveal in Finder     │                                             │
 │  └─────────────────────────┘                                             │
 │                                                                          │
 └─────────────────────────────────────────────────────────────────────────┘


 DATA FLOW
 ─────────

   User picks folder         File Tree renders          User double-clicks
   via NSOpenPanel            directory tree             a file
        │                          │                        │
        ▼                          ▼                        ▼
 ┌──────────────┐          ┌──────────────┐          ┌──────────────┐
 │  selectRoot  │          │  FileTree    │          │  FileTree    │
 │  Directory() │─────────▶│  ViewModel   │─────────▶│  ViewModel   │
 │              │          │              │          │   .open(     │
 │  WindowState.│          │  loads via   │          │    fileURL)  │
 │  activeWS    │          │  FileManager │          │      │       │
 │  Directory   │          │  on back-    │          └──────┼───────┘
 └──────────────┘          │  ground Task │                 │
                           └──────────────┘                 ▼
                                                     ┌──────────────┐
                                                     │ InterPanel   │
                                                     │ Router       │
                                                     │ .open(url)   │
                                                     │              │
                                                     │ routes to    │
                                                     │ module 3 / 4 │
                                                     │ / 5 / 8      │
                                                     └──────────────┘

   File operations      Drag & Drop                External changes
   (rename, delete,     (from tree to               (file added/
   new file/folder)      editor or vice              deleted by
        │                versa)                      another app / terminal)
        ▼                  ▼                            ▼
 ┌──────────────┐   ┌──────────────┐          ┌──────────────────┐
 │ FileManager  │   │ NSDragging   │          │ FSEventStream    │
 │ .move /      │   │ Session /    │          │ (CoreServices)   │
 │ .remove /    │   │ NSPasteboard │          │ fires for ALL    │
 │ .create      │   │              │          │ writers incl.    │
 │              │   │              │          │ POSIX/terminal   │
 └──────────────┘   └──────────────┘          └──────────────────┘
       │                  │                          │
       ▼                  ▼                          ▼
 ┌──────────────────────────────────────────────────────────────────┐
 │  ViewModel rebuilds tree from disk (single source of truth)      │
 └──────────────────────────────────────────────────────────────────┘
```

## Source Files
| File | Responsibility |
|---|---|
| `FileTreePanel.swift` | Top-level SwiftUI panel view — assembles header bar, search toggle, open-folder button, recursive tree list, drag-and-drop on root, keyboard shortcut overlay (⌘N, ⌘⇧N, ⏎, ⌘C), empty/error/loading placeholders |
| `FileTreeRowView.swift` | Single-row SwiftUI view — indented icon + disclosure chevron + name label + modification date; supports multi-select (⌘-click/⇧-click), inline rename (TextField on row), double-tap to open, drag source, drop target for directory nodes, context menu via `FileContextMenu` |
| `FileTreeViewModel.swift` | `@MainActor @Observable` class — owns root `FileTreeNode`, `selectedNodeIDs: Set<URL>`, `renamingNodeID: URL?`, `expandedNodeIDs`, search filter; scans directories via static `loadLevel(_:)` on background `Task`, manages file operations (create/rename/trash), drag-and-drop handler, `FileSystemWatcher` subscription with 300 ms debounce |
| `FileTreeNode.swift` | `Identifiable & Sendable & Hashable` value type — id (URL), name, isDirectory, children (lazy-loaded), fileType, modificationDate, isReadable; computed `icon` property returns SF Symbol name based on type/read-permission |
| `FileContextMenu.swift` | SwiftUI `View` for `.contextMenu` — New File, New Folder (directory only), Rename, Move to Trash (batch-trashes selected set), Copy Path, Reveal in Finder |
| `FileSystemWatcher.swift` | `final class` (`@unchecked Sendable`) — observes a directory for external changes via `FSEventStream` (CoreServices); fires for all writers including POSIX/terminal; emits affected URL through `AsyncStream`; emits sentinel `sputnik://watchedRootLost` on root removal; uses `NSLock` to guard `continuation` against concurrent `stop()` + callback races |
| `Package.swift` | SPM manifest — declares dependencies on `FoundationModule` and `SputnikShared` |

## Technical Summary

- **Framework(s):** SwiftUI (tree list, context menus, drag-and-drop), AppKit via `NSViewRepresentable` if large directory trees require virtualised performance (SW-3), Foundation `FileManager`, CoreServices `FSEventStream` (directory watching — fires for all writers including POSIX/terminal), `NSWorkspace` (Reveal in Finder, file icons)
- **Key types:**
  - `FileTreePanel` — top-level SwiftUI view; assembles the header, search bar, tree list, context menu, and keyboard shortcut overlay
  - `FileTreeNode` — `Identifiable` and `Sendable` struct representing a single file or folder; holds `id` (file URL), `name`, `isDirectory`, `children` (lazy-loaded on expansion), `icon`, `modificationDate`, and file status colour
  - `FileTreeViewModel` — `@Observable` class; owns the root `FileTreeNode` tree, the active directory URL, expanded node IDs, **`selectedNodeIDs: Set<URL>`** (multi-select), **`renamingNodeID: URL?`** (inline rename state), search filter text; loads directory contents on a background `Task(priority: .userInitiated)` and publishes updates on `@MainActor`
  - `FileTreeRowView` — SwiftUI `View` for each row; shows icon + name + **modification date** + disclosure chevron; supports multi-select (⌘-click, ⇧-click), **inline rename** (TextField replaces name label), drag source for files, and **drop target for directory nodes**
  - `FileContextMenu` — SwiftUI `Menu`/context menu builder; actions: New File, New Folder, **Rename (sets `renamingNodeID` to trigger inline field)**, Move to Trash (batch trashes all selected nodes), Copy Path, Reveal in Finder
  - `FileSystemWatcher` — `final class @unchecked Sendable`; observes the active directory via `FSEventStream` (CoreServices); fires for all writers including POSIX/terminal tools; emits changed URLs through `AsyncStream<URL>`; emits sentinel `sputnik://watchedRootLost` on root removal (`kFSEventStreamEventFlagRootChanged`); uses `NSLock` to guard `continuation` against concurrent `stop()` + callback races; delivered on a private `DispatchQueue`
- **Threading model:**
  - `@MainActor` for all view updates, selection changes, context menu actions, and drag-and-drop UI callbacks
  - **`Task.detached(priority: .userInitiated)`** for initial directory scanning (reading file attributes, building `FileTreeNode` hierarchy) — detached so `@MainActor` isolation is not inherited and `FileManager` I/O runs on the cooperative pool (ISS-104 verified at scanLevel :276)
  - **`Task.detached(priority: .background)`** for recursive subtree scanning when expanding large folders — results merged into the tree on `@MainActor` (ISS-104 verified at expandNode :107)
  - `FileSystemWatcher` callbacks arrive on its private `DispatchQueue`; events are forwarded to `FileTreeViewModel` via `AsyncStream` and processed on `@MainActor`; root-loss sentinel triggers immediate `handleRootLost()` via `MainActor.run`
- **Data flow:**
  1. **Folder selection** — user selects a folder via `NSOpenPanel` (or app launch restores last directory) → `windowState.activeWorkspaceDirectory` set → `FileTreeViewModel` begins scanning on background `Task`
  2. **Tree building** — `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)` → `FileTreeNode` tree built recursively (children loaded lazily on folder expansion) → tree published on `@MainActor` → SwiftUI `List` or `OutlineGroup` renders rows
  3. **Open file** — user double-clicks or presses Enter → `FileTreeViewModel.open(_:)` → `InterPanelRouter.open(url)` (Foundation 2.1) → opens/raises editor tab in appropriate module
  4. **File operations** — context menu action performed via `FileManager` → on success, `FileTreeViewModel` refreshes the affected subtree from disk; on failure, surfaces error via Foundation 2.4 `SputnikAlert`. **Batch trash** `trashSelected()` trashes all nodes in `selectedNodeIDs`; **inline rename** sets `renamingNodeID`, triggering a `TextField` on the row
  5. **Drag and drop** — drag from tree: `.onDrag` packages file URL into `NSItemProvider`; drop onto tree: `.onDrop` on the root `ScrollView` (external drops) **or on individual directory rows** (intra-tree folder-to-folder drops) calls `FileTreeViewModel.handleDrop(_:into:)`. **Intra-tree drops** (source URL is within the active directory tree) **move** the file via `FileManager.moveItem`; external drops **copy** via `FileManager.copyItem`
  6. **External sync** — `FSEventStream` callback fires (latency 0.25 s) → `changeStream` yields changed URL → debounced (additional 300 ms) → `FileTreeViewModel` reloads from disk → tree updates without losing expanded/selection state. If the root is removed, `kFSEventStreamEventFlagRootChanged` fires → sentinel yielded → `FileTreeViewModel.handleRootLost()` sets `rootUnavailable = true`, clears the tree, stops the watcher, sets `errorMessage = "Folder no longer available."`
- **Per-window workspace:** Because each window has its own `WindowState`, the File Tree reads `windowState.activeWorkspaceDirectory` rather than a global `AppState` property. This means each window can open a different project folder without affecting any other window's file tree. The `FileTreeViewModel` is configured per view instance via `viewModel.configure(windowState:)`.
- **State owned:**
  - `FileTreeViewModel` — root `FileTreeNode`, expanded node ID set (`Set<URL>`), **selected node IDs (`Set<URL>`)**, **renaming node ID (`URL?`)**, search filter text, active directory URL, **`rootUnavailable: Bool`** (set when watched root disappears)
  - `WindowState.activeWorkspaceDirectory` (Foundation 2.2) — the canonical root directory for this window; the File Tree reads it, never owns it
- **Keyboard shortcuts:** Hidden buttons in `FileTreePanel.keyboardShortcutOverlay` capture:
  - **⌘⌫** → `trashSelected()` (moves all selected nodes to Trash)
  - **⌘N** → `promptNewFile(in:)` (creates new file in active directory)
  - **⌘⇧N** → `promptNewFolder(in:)` (creates new folder in active directory)
  - **⏎** → `beginRenameSelected()` (starts inline rename on selected node)
  - **⌘C** → `copySelectedPaths()` (copies paths of all selected nodes to clipboard)
- **Multi-select:** Single-tap replaces selection; **⌘-click** toggles a node; **⇧-click** adds to selection. All context-menu operations (trash, copy path) operate on the full selection set.
- **Dependencies:** Foundation 2.2 (`AppState.activeDirectory`, `AppState.openDocuments` for file-status colouring), Foundation 2.1 (`InterPanelRouter.open(_:)`), Foundation 2.4 (error alerts, UI/UX primitives for icons and colours), Foundation 2.7 (Utilities for `DebounceTimer` via `SputnikShared`), SputnikShared (`DebounceTimer`); no dependency on modules 3, 4, 5, 7, or 8
- **Failure modes:**
  - Selected directory is deleted or becomes inaccessible while watched → `FSEventStream` fires `kFSEventStreamEventFlagRootChanged` → sentinel URL emitted → `FileTreeViewModel.handleRootLost()` sets `rootUnavailable = true` and `errorMessage = "Folder no longer available."` → tree cleared, watcher stopped, panel shows error placeholder (ISS-114). If the directory disappears between watcher stop and the next manual refresh, `FileManager.contentsOfDirectory` throws → same error state
  - Permission denied for a subdirectory → `FileManager` throws on that subtree → `FileTreeNode` shows that folder with a lock icon and empty children (does not crash the whole tree)
  - File operation (rename/delete) fails → catch `FileManager` error → display `SputnikAlert` with the system error message, leave tree unchanged
  - Drag-and-drop with unsupported content type → `.onDrop` returns `false` → drop is rejected silently by the system (standard macOS behaviour)
  - Extremely large directory (100,000+ files) → background `Task` loads in chunks, tree renders a subset initially with a "Loading more…" placeholder; `FileSystemWatcher` debounce prevents rapid re-scans

## Invariants
- `FileTreeViewModel` is `@MainActor` — all observable state mutations happen on the main actor; background `Task`s merge results via `@MainActor` (SW-1)
- File-tree scanning (`loadLevel(_:)`) is a **static** method on `FileTreeViewModel` — never captures `self`; all file-system I/O runs off the main thread (SW-4)
- The **only** file-open path to other panels is `InterPanelRouter.open(_:)` — never direct `WindowState.openDocument()` or `AppState.openDocuments` mutation (SR-1 per ISS-029)
- `FileTreeViewModel` holds **weak** references to `WindowState` and `InterPanelRouter` — no retain cycles (SW-2)
- `FileSystemWatcher` is `@unchecked Sendable` — `continuation` is guarded by `NSLock`; safe despite compiler annotation. All FSEvent callbacks fire on `FileSystemWatcher`'s private `DispatchQueue`; `emit(_:)` acquires the lock before yielding so `stop()` and the callback can never race (ISS-115)
- Drag-and-drop into a directory node **moves** files for intra-tree drops and **copies** for external drops — this is the only file-move path in the panel
- `FileTreeRowView` inline rename commits via `FileManager.moveItem` — never mutates the tree in memory without syncing to disk
- The panel renders **only** when a workspace directory is set — no phantom empty-state without user intent

## Spec Reference

> Extracted from `README.md` — the original bullet points for this module:

```
6. FILE EXPLORER = the area where users can browse and manage the folder and files to be edited or viewed
  1. Local folder selection
  2. File Status Coloring
  3. Local computer synchronization, 
  4. File System Operations (Right-click context menu to: Create New File, Create New Folder, Delete/Move to Trash, Rename).
  5. Drag-and-Drop Support (Dragging files into or out of the project tree, or reordering folders).
  6. File and Folder icons depending on format (eg folder open or closed, full or empty // eg files markdown, text, html, png etc)
```

> Module map entry (from `CLAUDE.md`):

```
| 6 | Project File Tree | Folder tree, file operations, drag-and-drop |
```

> Build order note — the File Tree is the 4th module to be implemented:

```
Foundation → Text Editor Window → Terminal → Project File Tree → Markdown Preview → PDF Viewer → HTML Preview → Resources
```
