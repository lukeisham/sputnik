---
module: 2.6 Foundation – App Lifecycle
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
---

## Purpose
Define the single app entry point and window architecture so every module has a consistent, reliable hook into launch, termination, and window events.

## Decision
**Option B — `@NSApplicationDelegateAdaptor` hybrid.**
SwiftUI `App` struct owns the view hierarchy; a traditional `AppDelegate` handles lifecycle events. Pure SwiftUI lifecycle was ruled out because Sputnik requires `applicationShouldTerminate` for PTY cleanup (module 7) and a reliable `applicationWillTerminate` hook to flush layout state to disk (module 2.5).

## Appearance / Function Diagram

```
@main SputnikApp: App
     │
     ├── @NSApplicationDelegateAdaptor  ──▶  AppDelegate: NSObject, NSApplicationDelegate
     │        │
     │        ├── applicationDidFinishLaunching  → PersistenceService.restore()
     │        │                                    → check crash-recovery files
     │        │                                    → SputnikMenuBarController() [held strongly]
     │        │                                    → processMonitor.start()
     │        │
     │        ├── applicationShouldTerminate      → AppState.allTerminalManagers
     │        │                                    → for each: manager.killAllPTYs() [concurrent]
     │        │                                    → returns .terminateLater until clean
     │        │
     │        └── applicationWillTerminate        → processMonitor.stop()
     │                                              → PersistenceService.flushLayout()
     │                                              → PersistenceService.saveWindows(descriptors)
     │
     └── App body (scenes)
              ├── WindowGroup (id: "main", for: UUID.self)  ← data-driven multi-instance scene
              │        └── ContentView(windowState, router)  ← root SwiftUI layout (all panels)
              │                 └── .focusedSceneValue(\.activeWindowID) ← frontmost tracking
              │                 └── .background { WindowRestorerView }   ← opens persisted windows
              │
              ├── Window("About Sputnik", id: "about")
              │        └── AboutWindowView               ← fixed size, no resize handle
              │                 └── .handlesExternalEvents(matching: [])  ← single instance
 ```

 ## Source Files
 | File | Responsibility |
 |---|---|
 | `SputnikApp.swift` | `@main` SwiftUI `App` struct — multi-window `WindowGroup`, About window scene, Settings scene, `@NSApplicationDelegateAdaptor` |
 | `ContentView.swift` | Root SwiftUI layout — three-column `HStack` + pinned Terminal + StatusBar + Scratchpad overlay |
 | `AppDelegate.swift` | `@MainActor NSApplicationDelegate` — launch restore, termination gate, flush on terminate |
 | `SputnikMenuBarController.swift` | `@MainActor` — owns `NSStatusItem` with satellite icon; spins on `isProcessing` |
 | `TerminalLifecycle.swift` | `@MainActor` protocol — `killAllPTYs()`; Foundation owns, Terminal provides conformance (SR-1) |

 ## Technical Summary

 - **`@main struct SputnikApp: App`** — entry point. Declares multi-window `WindowGroup(id: "main", for: UUID.self)`, About window, Settings scene, and `AppDelegate` via `@NSApplicationDelegateAdaptor`.
 - **Multi-window scene:** Creates one window per unique `UUID`; resolves matching `WindowState` from `AppState.windows`.
 - **`AppDelegate`** — `@MainActor NSObject + NSApplicationDelegate`. Launch: restore layout, start `SputnikMenuBarController` and `ProcessMonitor`. Termination: collect all `TerminalManager` instances via `AppState.allTerminalManagers`, `killAllPTYs()` concurrently via `TaskGroup`, return `.terminateLater` until clean. Flush: `PersistenceService.flushLayout()` and `saveWindows()` on terminate.
 - **`SputnikMenuBarController`** (`@MainActor`) — creates `NSStatusItem` with satellite template image; observes `AppState.isProcessing` via `withObservationTracking` with `[weak self]`.
 - **`WindowRestorerView`** — invisible helper attached via `.background { }` on `ContentView`; restores persisted windows.
 - **`ProcessMonitor`** — started at launch, injected via `.environment(processMonitor)`.
 - **`@MainActor` boundary** — all delegate methods are on the main thread.

 ## Invariants
 - `AppDelegate` is `@MainActor` — all delegate methods run on the main thread (SW-1)
 - Termination gate: collects `TerminalManager` instances via `AppState.allTerminalManagers` and calls `killAllPTYs()` concurrently — only when all PTYs confirm exit does `NSApp.replyToApplicationShouldTerminate(true)` fire (SR-2)
 - `SputnikMenuBarController` captures `[weak self]` in observation handler — no retain cycle (SW-2)
 - `ContentView` receives per-window `WindowState` via `.environment(windowState)` — never shared across windows (SR-1)
 - About window uses `.handlesExternalEvents(matching: [])` — single instance only

 ## Decision


