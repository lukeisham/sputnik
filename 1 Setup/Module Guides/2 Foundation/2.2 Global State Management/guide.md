---
module: 2.2 Foundation – Global State Management
status: active
last_updated: 2026-06-08
---

## Purpose
Provide a single, thread-safe source of truth for the app's active workspace directory and currently open file so all modules read consistent state without coordinating directly with each other.

## Diagram

```
                  ┌─────────────────────────────────┐
                  │  AppState  (@Observable @MainActor) │
                  │                                 │
                  │  activeWorkspaceDirectory: URL? │
                  │  currentlyOpenFile: URL?        │
                  │  currentlyOpenFileType: FileType│
                  └────────────┬────────────────────┘
                               │  observed via @Environment
              ┌────────────────┼────────────────────┐
              ▼                ▼                    ▼
     File Tree (6)     Text Editor (3)        Terminal (7)
     syncs dir         loads file             cds to dir

File system watcher (background Task)
     └── NSFilePresenter / FileManager events
              └──▶ Task { @MainActor in appState.update() }
                        ← ensures main-thread write
```

## Technical Summary
- **Framework(s):** SwiftUI (`@Observable`, `@Environment`), Foundation, Swift Concurrency
- **Key types:**
  - `AppState` — `@Observable @MainActor` class; the single instance is created in `SputnikApp` and injected into the view hierarchy via `.environment(appState)` <!-- assumed -->
  - `FileType` — enum shared with module 2.1; classifies the open file so panels know how to respond <!-- assumed -->
- **Threading model:** `AppState` is `@MainActor` — all reads and writes happen on the main thread. Background file-system events (from `NSFilePresenter`) dispatch to the main thread with `Task { @MainActor in … }` before mutating state (SW-1, SR-4).
- **Data flow:** Any module reads `AppState` via `@Environment`. Any module that triggers a state change (e.g. File Tree opening a file) writes through `InterPanelRouter` (2.1), which updates `AppState` — modules never write to `AppState` directly.
- **State owned:**
  - `activeWorkspaceDirectory: URL?` — the folder currently shown in File Tree and used as the terminal working directory.
  - `currentlyOpenFile: URL?` — the file loaded in the active editor or viewer panel.
  - `currentlyOpenFileType: FileType` — derived from `currentlyOpenFile`; used by panels to show or hide themselves.
- **Dependencies:** `InterPanelRouter` (2.1) is the only writer. All other modules are read-only consumers.
- **Failure modes:**
  - File-system watcher fires after the workspace directory is deleted → `activeWorkspaceDirectory` set to `nil`; panels show an empty/placeholder state; no crash.
  - `NSFilePresenter` event arrives on a background thread → always dispatched to `@MainActor` before mutating `AppState`; actor-isolation compiler error catches any violation at build time.

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  2. Global State Management
    1. Single Source of Truth (e.g., Observable pattern) to track the "Active Workspace Directory" and "Currently Open File."
    2. Thread Safety: Ensure terminal streaming data and file system watchers update state on the Main Thread safely.
```
