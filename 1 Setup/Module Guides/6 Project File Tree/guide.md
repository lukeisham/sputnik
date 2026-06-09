---
module: 6 Project File Tree
status: complete
last_updated: 2026-06-09
plan: 1 Setup/Plans Completed/2026-06-08 6 Project File Tree Implement Project File Tree module.md
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
        │                versa)                      another app)
        ▼                  ▼                            ▼
 ┌──────────────┐   ┌──────────────┐          ┌──────────────────┐
 │ FileManager  │   │ NSDragging   │          │ NSFilePresenter  │
 │ .move /      │   │ Session /    │          │  protocol         │
 │ .remove /    │   │ NSPasteboard │          │  .presentedItem  │
 │ .create      │   │              │          │  DidChange       │
 └──────────────┘   └──────────────┘          └──────────────────┘
       │                  │                          │
       ▼                  ▼                          ▼
 ┌──────────────────────────────────────────────────────────────────┐
 │  ViewModel rebuilds tree from disk (single source of truth)      │
 └──────────────────────────────────────────────────────────────────┘
```

## Technical Summary

- **Framework(s):** SwiftUI (tree list, context menus, drag-and-drop), AppKit via `NSOutlineView` or `NSViewRepresentable` if large directory trees require virtualised performance (SW-3), Foundation `FileManager`, `FilePresenter` protocol (MR-2), `NSWorkspace` (Reveal in Finder, file icons)
- **Key types:** <!-- all assumed — no source code exists yet -->
  - `FileTreePanel` — top-level SwiftUI view; assembles the header, search bar, tree list, and context menu
  - `FileTreeNode` — `Identifiable` and `Sendable` struct representing a single file or folder; holds `id` (file URL), `name`, `isDirectory`, `children` (lazy-loaded on expansion), `icon`, `modificationDate`, and file status colour
  - `FileTreeViewModel` — `@Observable` class; owns the root `FileTreeNode` tree, the active directory URL, expanded node IDs, search filter text, and selection state; loads directory contents on a background `Task(priority: .userInitiated)` and publishes updates on `@MainActor`
  - `FileTreeRowView` — SwiftUI `View` for each row; shows icon + name + status dot; applies file-status colouring based on git status or last-modified delta
  - `FileContextMenu` — SwiftUI `Menu`/context menu builder; actions: New File, New Folder, Rename, Move to Trash, Copy Path, Reveal in Finder
  - `FileDragDelegate` — `NSViewRepresentable` or SwiftUI `.onDrag`/`.onDrop` handler; packages file URLs onto `NSPasteboard` for drag-out and accepts dropped URLs for import or reorganisation
  - `FileSystemWatcher` — `NSObject` adopting `NSFilePresenter` protocol (MR-2); observes the active directory and its immediate subdirectory for external changes; publishes a notification stream that `FileTreeViewModel` subscribes to for tree refresh
- **Threading model:**
  - `@MainActor` for all view updates, selection changes, context menu actions, and drag-and-drop UI callbacks
  - Background `Task(priority: .userInitiated)` for initial directory scanning (reading file attributes, building `FileTreeNode` hierarchy)
  - Background `Task(priority: .background)` for recursive subtree scanning when expanding large folders — results merged into the tree on `@MainActor`
  - `FileSystemWatcher` callbacks arrive on an arbitrary queue; events are forwarded to `FileTreeViewModel` via a `@MainActor`-bound `AsyncStream` or explicit `MainActor.run`
- **Data flow:**
  1. **Folder selection** — user selects a folder via `NSOpenPanel` (or app launch restores last directory) → `windowState.activeWorkspaceDirectory` set → `FileTreeViewModel` begins scanning on background `Task`
  2. **Tree building** — `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)` → `FileTreeNode` tree built recursively (children loaded lazily on folder expansion) → tree published on `@MainActor` → SwiftUI `List` or `OutlineGroup` renders rows
  3. **Open file** — user double-clicks or presses Enter → `FileTreeViewModel.open(_:)` → `InterPanelRouter.open(url)` (Foundation 2.1) → opens/raises editor tab in appropriate module
  4. **File operations** — context menu action performed via `FileManager` → on success, `FileTreeViewModel` refreshes the affected subtree from disk; on failure, surfaces error via Foundation 2.4 `SputnikAlert`
  5. **Drag and drop** — drag from tree: `.onDrag` packages file URL into `NSItemProvider`; drop onto tree: `.onDrop` inspects `UTType`, copies or moves files via `FileManager`, then refreshes
  6. **External sync** — `FilePresenter` callback fires → debounced (300 ms) → `FileTreeViewModel` reloads affected directory → tree updates without losing expanded/selection state
- **Per-window workspace:** Because each window has its own `WindowState`, the File Tree reads `windowState.activeWorkspaceDirectory` rather than a global `AppState` property. This means each window can open a different project folder without affecting any other window's file tree. The `FileTreeViewModel` is configured per view instance via `viewModel.configure(windowState:)`.
- **State owned:**
  - `FileTreeViewModel` — root `FileTreeNode`, expanded node ID set, selected node ID, search filter text, active directory URL
  - `WindowState.activeWorkspaceDirectory` (Foundation 2.2) — the canonical root directory for this window; the File Tree reads it, never owns it
- **Dependencies:** Foundation 2.2 (`AppState.activeDirectory`, `AppState.openDocuments` for file-status colouring), Foundation 2.1 (`InterPanelRouter.open(_:)`), Foundation 2.4 (error alerts, UI/UX primitives for icons and colours), Foundation 2.7 (Utilities for path helpers); no dependency on modules 3, 4, 5, 7, or 8
- **Failure modes:**
  - Selected directory is deleted or becomes inaccessible → `FileManager.contentsOfDirectory` throws on next refresh → `FileTreeViewModel` sets error state → placeholder view with "Directory unavailable" message and "Select Different Folder" button
  - Permission denied for a subdirectory → `FileManager` throws on that subtree → `FileTreeNode` shows that folder with a lock icon and empty children (does not crash the whole tree)
  - File operation (rename/delete) fails → catch `FileManager` error → display `SputnikAlert` with the system error message, leave tree unchanged
  - Drag-and-drop with unsupported content type → `.onDrop` returns `false` → drop is rejected silently by the system (standard macOS behaviour)
  - Extremely large directory (100,000+ files) → background `Task` loads in chunks, tree renders a subset initially with a "Loading more…" placeholder; `FileSystemWatcher` debounce prevents rapid re-scans

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
