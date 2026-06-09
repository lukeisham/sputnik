---
module: 2.2 Foundation – Global State Management
status: active
last_updated: 2026-06-09
---

## Purpose
Provide a single, thread-safe source of truth for the app's active workspace directory and all open document tabs so every module reads consistent state without coordinating directly with each other.

## Diagram

```
                  ┌──────────────────────────────────────────┐
                  │  AppState  (@Observable @MainActor)       │
                  │                                          │
                  │  activeWorkspaceDirectory: URL?          │
                  │  openDocuments: [DocumentSession]  ◀─────┼── tab bar (2.4)
                  │  activeDocumentID: UUID?           ◀─────┼── tab bar (2.4)
                  │  activeDocument: DocumentSession?        │
                  │  focusMode: FocusMode                    │
                  │  isProcessing: Bool (computed)     ◀─────┼── StatusBarView / MenuBarController
                  │  contextUsage: ContextUsage?       ◀─────┼── StatusBarView CTX %
                  │  scratchpadVisible: Bool           ◀─────┼── ScratchpadPanel / View menu
                  └─────────────┬────────────────────────────┘
                                │  observed via @Environment
             ┌──────────────────┼──────────────────────┐
             ▼                  ▼                      ▼
    File Tree (6)       Text Editor (3)          Terminal (7)
    syncs dir       binds to activeDocument      cds to dir
                         ▼             ▼
                 HTML Preview (8)  Markdown Preview (4)
                 renders .html     renders .markdown

InterPanelRouter (2.1) — sole writer for openDocuments / activeDocumentID
File system watcher (background Task)
     └── NSFilePresenter / FileManager events
              └──▶ Task { @MainActor in appState.update() }
```

## Technical Summary
- **Framework(s):** SwiftUI (`@Observable`, `@Environment`), Foundation, Swift Concurrency
- **Key types:**
  - `AppState` — `@Observable @MainActor` class; single instance created in `SputnikApp`,
    injected via `.environment(appState)`
  - `DocumentSession` — `@Observable @MainActor` class; one instance per open tab,
    owning `id`, `url`, `fileType`, `text`, and `isDirty`
  - `FileType` — enum shared with module 2.1; classifies a session so panels render correctly
  - `ContextUsage` (`Sendable`, `2 Foundation/2.2 Global State Management/ContextUsage.swift`) — `usedTokens: Int`, `contextWindow: Int`, computed `percent: Double`; written to `AppState.contextUsage` by any module making AI calls; context window size looked up from `ModelCapacity` (2.3); `nil` when no AI call is active
- **Threading model:** `AppState` and `DocumentSession` are `@MainActor` — all reads and
  writes are on the main thread. Background file-system events must hop via
  `Task { @MainActor in … }` before mutating state (SW-1, SR-4).
- **Data flow:** All modules read `AppState` via `@Environment`. Any module that triggers
  a document change (File Tree opening a file, preview link click) writes through
  `InterPanelRouter` (2.1) — modules never mutate `openDocuments` or `activeDocumentID`
  directly. Foundation-layer views (toolbar, `DocumentTabBar`) may write `activeDocumentID`
  and `focusMode` directly as they are part of the same layer.
- **State owned (resolves ISS-005):**
  - `activeWorkspaceDirectory: URL?` — folder shown in File Tree / Terminal working dir.
  - `openDocuments: [DocumentSession]` — ordered list driving the tab bar.
  - `activeDocumentID: UUID?` — which tab is active; `nil` = no open documents.
  - `activeDocument: DocumentSession?` — computed from `activeDocumentID`.
  - `focusMode: FocusMode` — written by toolbar.
  - `currentlyOpenFile: URL?` — read-only computed alias of `activeDocument?.url`.
  - `currentlyOpenFileType: FileType` — read-only computed alias of `activeDocument?.fileType`.
  - `requestedHelpTarget: HelpRequest?` — the live help-routing primitive (resolves ISS-008). `nil` when no help is open; set by the Help menu (with `topicID = nil`) or by the editor's "Look Up Help" action (with a resolved `topicID`). Module 9 panels observe this to reveal and navigate. The backward-compatible computed property `requestedHelpTopic: HelpTopic?` overlays it for callers that only need the panel kind (e.g. the Help menu, the right-column switch in `ContentView`).
  - `private var processingCount: Int` — reference count of concurrent in-flight operations; always mutated on `@MainActor` so no race is possible.
  - `isProcessing: Bool` — **computed**: `processingCount > 0`; observed by `StatusBarView` (F-5) for the satellite spinner and by `SputnikMenuBarController` (F-1) for the menu-bar animation; single source of truth for "the app is busy" across both display surfaces (SR-1, resolves ISS-013).
  - `func beginProcessing()` / `func endProcessing()` — increment / decrement `processingCount`; callers must balance every `begin` with an `end` (document at call sites).
  - `contextUsage: ContextUsage?` — written by any module making AI calls; consumed by `StatusBarView` context-% segment; `nil` when no AI call is in progress or no model is configured.
  - `scratchpadVisible: Bool` — toggled by **View ▸ Scratchpad** (⌘⇧K) via `SputnikCommands`; observed by `ScratchpadPanel` (2.4) to show/hide the overlay; initial value restored from `PersistenceService` on launch.
- **Dependencies:** `InterPanelRouter` (2.1) is the sole external writer. Foundation-layer
  UI (toolbar, `DocumentTabBar`) may write `activeDocumentID` and `focusMode` directly.
- **Failure modes:**
  - File-system watcher fires after workspace directory deleted → `activeWorkspaceDirectory`
    set to `nil`; panels show placeholder; no crash.
  - `NSFilePresenter` event on background thread → dispatched to `@MainActor` before
    mutation; actor isolation catches violations at compile time.
  - `activeDocumentID` references a session that was removed → `activeDocument` returns
    `nil`; panels show placeholder; no stale rendering.

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  2. Global State Management
    1. Single Source of Truth (e.g., Observable pattern) to track the
       "Active Workspace Directory" and "Currently Open File."
    2. Thread Safety: Ensure terminal streaming data and file system watchers
       update state on the Main Thread safely.
```
