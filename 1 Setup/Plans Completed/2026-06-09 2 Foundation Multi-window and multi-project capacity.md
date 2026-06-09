---
plan: Multi-window and multi-project capacity
module: 2 Foundation (2.2 / 2.6 / 2.0 / 2.4) + 7 Terminal + 6 Project File Tree
created: 2026-06-09
status: complete
related_issues: none
---

## Purpose
Enable Sputnik to open multiple independent windows, each with its own project folder, its own set of tabs, and its own terminal session — so a user can work on separate projects side by side without any shared state between windows.

## Success Condition
- **File > New Window** (⇧⌘N) opens a second, empty window with its own placeholder state (no tabs, no workspace directory).
- Each window independently picks a workspace folder via the File Tree, opens its own tabs, and runs its own Zsh terminal in that project's root.
- Switching between windows preserves each window's tabs, active document, and terminal state intact.
- Closing one window does not affect the other window's tabs, terminal, or workspace.
- **Window > Move Tab to New Window** and **Window > Merge All Windows** are wired and functional.
- Quitting the app (⌘Q) kills all PTYs across all windows and persists each window's open-tab list so they restore on next launch.

## Steps

- [ ] 1. **Define `WindowState` — per-window state container (2.2)**
   What: Create a new `@Observable @MainActor class WindowState` in `2 Foundation/2.2 Global State Management/WindowState.swift`. It holds:
   - `id: UUID` (stable identity for the window)
   - `title: String` (derived from workspace directory name, or "Untitled")
   - `openDocuments: [DocumentSession]` (tabs in this window)
   - `activeDocumentID: UUID?`
   - `activeWorkspaceDirectory: URL?`
   - `focusMode: FocusMode`
   - `requestedHelpTarget: HelpRequest?`
   - `scratchpadVisible: Bool`, `scratchpadText: String`, `scratchpadFrame: CGRect`
   - `layout: LayoutState` (panel arrangement per window)
   - A reference to this window's `TerminalManager` (created lazily)
   - `isProcessing: Bool` with `beginProcessing()`/`endProcessing()` (per-window AI state)
   - `contextUsage: ContextUsage?`
   
   Why: Every window must be fully independent. A single `AppState` singleton cannot represent "two projects, two tab sets, two terminals." `WindowState` is the unit of independence — one per window.

- [ ] 2. **Refactor `AppState` from singleton to window coordinator (2.2)**
   What: Replace `AppState`'s current per-window properties with a dictionary of `WindowState` instances:
   - Add `windows: OrderedDictionary<UUID, WindowState>` (or `[UUID: WindowState]` + `orderedWindowIDs: [UUID]`)
   - Add `activeWindowID: UUID?` — tracks which window is frontmost
   - Add computed `activeWindow: WindowState?` from `activeWindowID`
   - Migrate the current property list:
     - `openDocuments` → `activeWindow?.openDocuments ?? []`
     - `activeDocumentID` → `activeWindow?.activeDocumentID`
     - `activeDocument` → `activeWindow?.activeDocument`
     - `activeWorkspaceDirectory` → `activeWindow?.activeWorkspaceDirectory`
     - `currentlyOpenFile` → `activeWindow?.currentlyOpenFile`
     - `currentlyOpenFileType` → `activeWindow?.currentlyOpenFileType`
     - `layout` → `activeWindow?.layout ?? .default`
     - `requestedHelpTarget` → `activeWindow?.requestedHelpTarget`
     - `requestedHelpTopic` → `activeWindow?.requestedHelpTopic`
     - `isProcessing` becomes a computed that ORs all windows' processing states (for the menu bar icon)
     - `contextUsage` stays global (or moves to active window — decide during implementation)
     - `scratchpadVisible/Text/Frame` — these can be per-window inside `WindowState` or global. Decision: **per-window** (each window has its own scratchpad).
   - Keep on `AppState`: `terminalModelInfo` (global — it's about model detection, not window-specific), the window-creation/close methods, and the recent-files list (could stay global or become per-window — **decision: keep global** since it's Finder-level, not window-level).
   
   Why: This is the central structural change. `AppState` becomes a coordinator that knows about all windows; each `WindowState` is fully self-contained. All existing code that reads `@Environment(AppState.self).activeDocument` continues to compile via the computed accessors — but those now read from the active window's state.

- [ ] 3. **Add window lifecycle methods to `AppState` (2.2)**
   What: Add these methods:
   - `createWindow() -> WindowState` — creates a new `WindowState` with a fresh UUID, adds it to `windows`, sets `activeWindowID`, and returns it.
   - `closeWindow(_ id: UUID)` — removes the window, checks for dirty tabs, kills its terminal session, and selects a new `activeWindowID` (or `nil` if last window).
   - `windowForID(_ id: UUID) -> WindowState?` — lookup.
   - `activeWindowID` observation — wire a `Notification` or use SwiftUI's `focusedSceneValue` to detect when the frontmost window changes and update `activeWindowID`.
   
   Why: The app needs a defined lifecycle for each window — creating one, tracking focus, and tearing it down (including its terminal session) when closed.

- [ ] 4. **Upgrade `WindowGroup` for multi-instance scenes (2.6)**
   What: In `SputnikApp`, change the main scene from a single `WindowGroup` to a data-driven multi-window `WindowGroup`:
   
   ```swift
   WindowGroup(id: "main", for: UUID.self) { $windowID in
       ContentView(windowState: appState.windowForID(windowID.wrappedValue))
           .environment(appState)
           .environment(settingsStore)
           .environment(processMonitor)
   }
   .commands { SputnikCommands(appState: appState, settings: settingsStore) }
   ```
   
   The `ContentView` initializer receives its `WindowState` directly (not via `@Environment` for the window-scoped state) and passes it down. Remove `.handlesExternalEvents(matching: [])` — this is what currently blocks multiple windows.
   
   Why: SwiftUI's `WindowGroup(for:)` is the documented way to get multiple, data-driven windows. Each scene instance gets its own view hierarchy and its own `WindowState`.

- [ ] 5. **Wire the "New Window" menu command (2.0)**
   What: In `SputnikCommands`, implement the currently-stubbed `Button("New Window")`:
   - Call `appState.createWindow()` to get a new `WindowState`
   - Open a window for its UUID via `openWindow(value:)` using the environment's `openWindow` action
   - Remove `.disabled(true)` from the button
   
   Why: This is the primary way users create new windows. The stub says "multi-window is a future feature" — now it becomes present.

- [ ] 6. **Wire "Move Tab to New Window" and "Merge All Windows" (2.0)**
   What:
   - "Move Tab to New Window": Detach the `activeDocumentID` `DocumentSession` from the current `WindowState`, create a new `WindowState` via `createWindow()`, move the session to it, open the window. Remove `.disabled(true)`.
   - "Merge All Windows": Collect all tabs from all windows into a single window's `openDocuments` list. Close all other windows (killing their terminals). Remove `.disabled(true)`.
   
   Why: These are standard macOS multi-window interactions. Users expect them to work.

- [ ] 7. **Per-window file tree (6)**
   What: `FileTreePanel` currently reads `AppState.activeWorkspaceDirectory`. Change it to receive its window's `WindowState` (via environment or initializer injection) and read `windowState.activeWorkspaceDirectory` instead. The file tree's expanded-nodes and selection state naturally become per-window since each `FileTreePanel` instance lives in its own window's view hierarchy.
   
   Why: Each window needs its own workspace directory. Without this, opening a project in window A would also change the file tree in window B.

- [ ] 8. **Per-window terminal (7)**
   What: Currently `TerminalView` creates a single `@StateObject private var manager = TerminalManager()` — this already produces one manager per view instance, so each window would automatically get its own terminal. However, two things must change:
   - `TerminalManager` must be stored on `WindowState` (or owned by the window's view hierarchy) so it is not recreated on view redraws.
   - The `cd` sync: `TerminalView` currently observes `AppState.activeWorkspaceDirectory` for directory changes. Change this to observe `windowState.activeWorkspaceDirectory`.
   - `AppDelegate.applicationShouldTerminate` currently calls `terminalLifecycle.killAllPTYs()`. This needs to collect all `TerminalManager` instances from all `WindowState`s. Approach: add `allTerminalManagers: [TerminalManager]` computed property to `AppState`, and update `TerminalLifecycle` adapter to iterate over all of them.
   
   Why: Each window gets its own shell session in its own project directory. No terminal state leaks between windows.

- [ ] 9. **Per-window document and layout persistence (2.5)**
   What: Extend `PersistenceService` to persist per-window state:
   - Persist a list of window descriptors, each containing: `id: UUID`, `workspaceDirectoryURL: URL?`, `openTabURLs: [URL]`, `activeDocumentID: UUID`, `layout: LayoutState`
   - On launch, restore all windows (recreating `WindowState` instances for each saved window descriptor).
   - On quit, flush all windows' state.
   - The existing `PersistenceService` API already handles key-value storage — extend with a `saveWindows(_:)` / `restoreWindows() -> [WindowDescriptor]` pair.
   
   Why: Without persistence, windows vanish on relaunch, which breaks the "foundational" expectation. Users who carefully set up two project windows expect to find them again.

- [ ] 10. **Update status bar, scratchpad, and help routing (2.4)**
   What: 
   - `StatusBarView` currently reads `AppState` for `isProcessing` and `contextUsage`. Change to read from its `WindowState` for per-window AI state. RAM/CPU (`ProcessMonitor`) stays global.
   - `ScratchpadPanel` currently reads `appState.scratchpadVisible/Text/Frame`. Change to read from `windowState` instead (each window gets its own scratchpad).
   - Help routing (`requestedHelpTarget`) moves to `WindowState` so each window independently shows/hides help panels. The right column in `ContentView` already toggles based on this — it will naturally work per-window once `ContentView` reads from its `WindowState`.
   
   Why: Every panel in the window that was reading global `AppState` properties must now read from its own `WindowState`.

- [ ] 11. **Handle frontmost-window tracking (2.6)**
   What: When the user clicks between windows, `activeWindowID` on `AppState` must update so that menu commands (which read `appState`) target the correct window. Approaches (pick one):
   - **Option A (recommended):** Use `@FocusedValue` in SwiftUI — each `ContentView` exposes its `WindowState.id` as a focused value. `SputnikCommands` reads the focused value to determine which window to act on.
   - **Option B:** Observe `NSApplication.keyWindow` changes in `AppDelegate` and map to the matching `WindowState` by tracking `NSWindow.identifier`.
   
   Why: Menu commands like "Close Tab", "Close Window", and the View menu's layout toggles must operate on the frontmost window, not a stale reference.

- [ ] 12. **Update all Module Guides**
   What: Update these guides with the new architecture:
   - **2.2 Global State Management** — document `WindowState`, `AppState` as coordinator, computed accessors
   - **2.6 App Lifecycle** — update the diagram to show multi-window `WindowGroup`, updated `AppDelegate` (collects PTYs from all windows)
   - **2.0 App Overview** — update menu descriptions for "New Window", "Move Tab", "Merge All Windows"
   - **7 Terminal** — document per-window `TerminalManager`, updated `killAllPTYs` flow
   - **6 Project File Tree** — document per-window workspace directory
   - Bump `last_updated` on all; set status to `active` (or `complete` where appropriate)
   
   Why: Guides are the source of truth (SR-1, working conventions). Leaving them stale would re-introduce the very gaps this plan closes.

## Risks and Constraints
- **Touches Foundation (module 2) — flagged per !GenerateAPlan rule.** Changes to `AppState`, the scene declaration, and the menu commands affect every consuming module. All existing callers of `@Environment(AppState.self).xxxx` must be verified to continue working (either via computed pass-through or by injecting `WindowState`).
- **Terminal lifecycle is critical.** Collecting all `TerminalManager` instances from all windows during `applicationShouldTerminate` must not retain them. Use a weak collection or a registration pattern to avoid leaking windows on close.
- **Backward compatibility with existing tab model.** The `WindowState` class should mirror `AppState`'s current document-management API (`openDocument(url:)`, `newUntitledDocument()`, `closeDocument(_:)`) so existing callers (DocumentsTabBar, InterPanelRouter) can be migrated by simply changing the target from `appState` to `windowState`.
- **SR-3 (Low RAM):** Each window with open tabs holds its documents in memory. The existing file-size guard per tab (module 3) still applies. With N windows, worst-case RAM = N × (max tabs × max file size). Acceptable for typical use (2–4 windows, small to medium files).
- **SW-2 (Retain cycles):** `WindowGroup` holds a strong reference to the window's content view, which holds `WindowState` via environment. The `TerminalManager` stored on `WindowState` must use `[weak self]` in its `AsyncStream` listener to avoid keeping the whole window alive. Same for any `AppState` → `WindowState` back-references.
- **No IPC between windows** — by design. Each window is fully independent. This avoids complexity of locks, conflict resolution, or cross-window state sync.
- **`SputnikMenuBarController`** currently observes `appState.isProcessing` (a single bool). With multi-window, `isProcessing` becomes `true` if *any* window is processing. The computed property on `AppState` handles this naturally.

## Files Affected
- `2 Foundation/2.2 Global State Management/WindowState.swift` — **new** per-window state container
- `2 Foundation/2.2 Global State Management/AppState.swift` — refactor: add `windows`, `activeWindowID`, computed pass-throughs; add `createWindow()`, `closeWindow(_:)`, `windowForID(_:)`
- `2 Foundation/2.6 App Lifecycle/SputnikApp.swift` — change `WindowGroup` to data-driven multi-instance; remove `.handlesExternalEvents`
- `App-Sputnik/ContentView.swift` — accept `windowState` parameter; pass to child views; use `windowState` for scratchpad, help routing, layout
- `2 Foundation/2.0 App Overview/SputnikCommands.swift` — implement "New Window", "Move Tab to New Window", "Merge All Windows"
- `6 Project File Tree/FileTreePanel.swift` — read `windowState.activeWorkspaceDirectory` instead of global `appState`
- `7 Terminal/TerminalView.swift` — observe `windowState.activeWorkspaceDirectory` instead of global `appState`; store `TerminalManager` on `WindowState`
- `7 Terminal/TerminalManager.swift` — may need a registration method so `AppDelegate` can collect all managers for termination
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — update termination flow to collect PTYs from all windows
- `2 Foundation/2.6 App Lifecycle/TerminalLifecycle.swift` — review if protocol needs updating for multi-window
- `2 Foundation/2.5 Persistence/PersistenceService.swift` — add `saveWindows(_:)` / `restoreWindows() -> [WindowDescriptor]`
- `2 Foundation/2.4 UI and UX/StatusBarView.swift` — read per-window `isProcessing`/`contextUsage` from `windowState`
- `2 Foundation/2.4 UI and UX/ScratchpadPanel.swift` — read scratchpad state from `windowState`
- `2 Foundation/2.3 Settings/SettingsStore.swift` — no change (settings stay global)
- Module Guides: `2.2`, `2.6`, `2.0`, `7`, `6` — all updated

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (each step's acceptance criteria confirmed)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation + 6 + 7] Multi-window and multi-project capacity`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
