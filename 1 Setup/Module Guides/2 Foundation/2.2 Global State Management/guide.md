---
module: 2.2 Foundation – Global State Management
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
---

## Purpose
Provide per-window state containers and a top-level coordinator so that each Sputnik window operates independently — with its own workspace directory, document tabs, terminal session, scratchpad, layout, and AI state — while existing callers continue to compile against the familiar `AppState` interface.

## Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  AppState  (@Observable @MainActor — coordinator)                   │
│                                                                     │
│  windows: [UUID: WindowState]          orderedWindowIDs: [UUID]     │
│  activeWindowID: UUID?  ◀── @FocusedValue from frontmost ContentView │
│  activeWindow: WindowState? (computed)                              │
│                                                                     │
│  Computed pass-throughs → activeWindow.*                            │
│  createWindow() / closeWindow(_:) / windowForID(_:)                  │
│  allTerminalManagers: [any TerminalLifecycle] (for quit)            │
│  restoreWindows(from:) / collectDescriptors()  (for persistence)    │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ owns / coordinates
       ┌───────────────────┼───────────────────────┐
       ▼                   ▼                       ▼
 ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
 │ WindowState  │   │ WindowState  │   │ WindowState  │  … one per window
 │  (window 1)  │   │  (window 2)  │   │  (window 3)  │
 └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
        │                   │                   │
        │  Each WindowState holds:             │
        │  ─────────────────────────           │
        │  id: UUID                            │
        │  activeWorkspaceDirectory: URL?      │
        │  openDocuments: [DocumentSession]    │
        │  activeDocumentID: UUID?             │
        │  layout: LayoutState                 │
        │  terminalManager: (any TerminalLifecycle)?
        │  scratchpadVisible/Text/Frame         │
        │  requestedHelpTarget: HelpRequest?    │
        │  isProcessing: Bool (per-window AI)   │
        │  mainAIState: MainAIState?            │
        ▼                   ▼                   ▼
 File Tree (6)       Text Editor (3)       Terminal (7)
 reads windowState   reads windowState    reads windowState
 .activeWorkspaceDir .activeDocument      .activeWorkspaceDir
                                          .terminalManager
```

## Source Files
| File | Responsibility |
|---|---|
| `AppState.swift` | `@Observable @MainActor` — window coordinator owning `[UUID: WindowState]`, active window tracking, computed pass-throughs, `beginProcessing()`/`endProcessing()`, window lifecycle |
| `WindowState.swift` | `@Observable @MainActor` — per-window state: workspace directory, open documents, active document ID, layout, scratchpad, help routing, processing count, main AI state, terminal manager |
| `DocumentSession.swift` | `@Observable @MainActor` — per-tab model: id, url, fileType, text, isDirty |
| `EditorCommandHandling.swift` | `@MainActor` protocol — `save()`, `saveAs(to:)`, `renderAsHTML()`, `showASCIIStudio()` |
| `SupportingAIUsage.swift` | `Sendable` struct — `totalTokensSinceLaunch: Int`, `contextWindow: Int` |
| `MainAIState.swift` | `Sendable` struct — `modelName: String`, `contextWindow: Int?`, `usage: MainAIContextUsage?` |
| `TerminalModelInfo.swift` | Deprecated — superseded by `MainAIState` |
| `ContextUsage.swift` | Deprecated — superseded by `MainAIContextUsage` |

## Technical Summary
- **Framework(s):** SwiftUI (`@Observable`, `@Environment`, `@FocusedValue`), Foundation, Swift Concurrency
- **Key types:**
  - `AppState` — `@Observable @MainActor` class; **window coordinator** owning a dictionary of `WindowState` instances. Created once in `SputnikApp`, injected via `.environment(appState)`. Provides computed pass-through properties.
  - `WindowState` — `@Observable @MainActor` class; one per open window. Holds workspace directory, open documents, active document ID, layout, scratchpad, help routing, processing count, main AI state, terminal manager.
  - `ActiveWindowIDKey` — `FocusedValueKey` for `UUID`; set by `ContentView` for frontmost-window tracking.
  - `DocumentSession` — `@Observable @MainActor` class; one per open tab: `id`, `url`, `fileType`, `text`, `isDirty`.
  - `FileType` — enum shared with 2.1; classifies sessions for panel routing.
  - `SupportingAIUsage` — `Sendable` struct for Supporting AI metrics.
  - `MainAIState` — `Sendable` struct for Main AI model detection and usage.
  - `WindowDescriptor` — `Codable` struct for persisting a window's snapshot.
- **Threading model:** Both `AppState` and `WindowState` are `@MainActor` — all reads and
  writes are on the main thread. Background file-system events must hop via
  `Task { @MainActor in … }` before mutating state (SW-1, SR-4).
  Neither class conforms to `Sendable` — `@MainActor` isolation provides the safety.
  Do **not** add `@unchecked Sendable`; it would suppress data-race detection without
  providing any safety benefit.
  (Resolves ISS-052.)
- **Data flow:**
  - Each `ContentView` receives its `WindowState` via `.environment(windowState)`.
  - Panels read from `@Environment(WindowState.self)` for per-window state (workspace directory,
    active document, scratchpad).
  - Modules that only need the *active* window's data (menu commands, `StatusBarView`) read via
    `@Environment(AppState.self)` and the computed pass-throughs.
  - Frontmost-window tracking uses `@FocusedValue`, reported back via `AppState.setActiveWindow(_:)`. Window-specific views read `@Environment(WindowState.self)`. Any module that triggers
  a document change (File Tree opening a file, preview link click) writes through
  `InterPanelRouter` (2.1) — modules never mutate `openDocuments` or `activeDocumentID`
  directly. Foundation-layer views (toolbar, `DocumentTabBar`) may write `activeDocumentID`
  directly as they are part of the same layer.
- **State owned (resolves ISS-005):**
  - `activeWorkspaceDirectory: URL?` — folder shown in File Tree / Terminal working dir.
  - `openDocuments: [DocumentSession]` — ordered list driving the tab bar.
  - `activeDocumentID: UUID?` — which tab is active; `nil` = no open documents.
  - `activeDocument: DocumentSession?` — computed from `activeDocumentID`.
  - `currentlyOpenFile: URL?` — read-only computed alias of `activeDocument?.url`.
  - `currentlyOpenFileType: FileType` — read-only computed alias of `activeDocument?.fileType`.
  - `requestedHelpTarget: HelpRequest?` — the live help-routing primitive (resolves ISS-008). `nil` when no help is open; set by the Help menu (with `topicID = nil`) or by the editor's "Look Up Help" action (with a resolved `topicID`). Module 9 panels observe this to reveal and navigate. The backward-compatible computed property `requestedHelpTopic: HelpTopic?` overlays it for callers that only need the panel kind (e.g. the Help menu, the right-column switch in `ContentView`).
  - `private var processingCount: Int` — reference count of concurrent in-flight operations; always mutated on `@MainActor` so no race is possible.
  - `isProcessing: Bool` — **computed**: `processingCount > 0`; observed by `StatusBarView` (F-5) for the satellite spinner and by `SputnikMenuBarController` (F-1) for the menu-bar animation; single source of truth for "the app is busy" across both display surfaces (SR-1, resolves ISS-013).
  - `func beginProcessing()` / `func endProcessing()` — increment / decrement `processingCount`; callers must balance every `begin` with an `end` (document at call sites).
  - `supportingAIUsage: SupportingAIUsage?` — cumulative Supporting AI token usage for the current session; `nil` until the first Supporting AI API call completes; written by `SupportingAIMonitor` (2.7) only (SR-1); consumed by `SupportingAISettingsView` for the Usage (This Session) metrics section
  - `mainAIState: MainAIState?` — Main AI state (the user-loaded AI in the terminal); `nil` when no Main AI is active; written by `MainAIMonitor` (2.7) only (SR-1); consumed by `StatusBarView` for the Main AI model name + CTX % segment
  - `scratchpadVisible: Bool` — toggled by **View ▸ Scratchpad** (⌘⇧K) via `SputnikCommands`; observed by `ScratchpadPanel` (2.4) to show/hide the overlay; initial value restored from `PersistenceService` on launch.
- **Dependencies:** `InterPanelRouter` (2.1) is the sole external writer. Foundation-layer
  UI (toolbar, `DocumentTabBar`) may write `activeDocumentID` directly.
- **Failure modes:**
  - File-system watcher fires after workspace directory deleted → `activeWorkspaceDirectory`
    set to `nil`; panels show placeholder; no crash.
  - `NSFilePresenter` event on background thread → dispatched to `@MainActor` before
    mutation; actor isolation catches violations at compile time.
  - `activeDocumentID` references a session that was removed → `activeDocument` returns
    `nil`; panels show placeholder; no stale rendering.

## Invariants
- `AppState` and `WindowState` are both `@MainActor` — all reads and writes are on the main thread (SW-1)
- Neither `AppState` nor `WindowState` conforms to `Sendable` — `@MainActor` isolation provides safety; do **not** add `@unchecked Sendable` (resolves ISS-052)
- Modules never write to `AppState.openDocuments` or `WindowState.openDocuments` directly — all file-open events flow through `InterPanelRouter` (2.1) (SR-1)
- `beginProcessing()`/`endProcessing()` must be balanced — each `begin` must have a matching `end` (SR-2)
- Frontmost-window tracking uses `@FocusedValue` only — no `NSApplication` delegate callbacks for window focus (SW-3)
- `WindowDescriptor` is the sole persistence contract — no other module serialises its own window state

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  2. Global State Management
    1. Single Source of Truth (e.g., Observable pattern) to track the
       "Active Workspace Directory" and "Currently Open File."
    2. Thread Safety: Ensure terminal streaming data and file system watchers
       update state on the Main Thread safely.
```
