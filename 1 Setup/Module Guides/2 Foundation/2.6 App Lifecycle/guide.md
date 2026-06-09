---
module: 2.6 Foundation – App Lifecycle
status: active
last_updated: 2026-06-09
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
              │
              └── Settings { SettingsView }
                       └── Appearance, Editor, Spelling, Terminal tabs
```

## Technical Summary

- **`@main struct SputnikApp: App`** — entry point. Declares the `WindowGroup` (multi-instance, data-driven), the `Window("About Sputnik", id: "about")` scene, and attaches `AppDelegate` via `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`. Commands are attached via `.commands { SputnikCommands(appState:appState, settings:settingsStore) }`.
- **Multi-window scene:** `WindowGroup(id: "main", for: UUID.self) { $windowID in … }` creates a new window instance for each unique `UUID` value that is passed to `openWindow(id: "main", value:)`. The closure resolves the matching `WindowState` from `AppState.windows`, falling back to the active window or creating a new one if none exists. Each window receives its own `WindowState` via `.environment(windowState)`. No `.handlesExternalEvents(matching:)` on the main scene — multi-window is intentional.
- **`AppDelegate`** — `NSObject` + `NSApplicationDelegate`. Does not own any views. Responsibilities:
  1. **Launch** — calls `PersistenceService.restore()`, surfaces crash-recovery dialog if needed, and instantiates `SputnikMenuBarController` (held as a `strong` property for app lifetime).
  2. **Termination gate** — collects all `TerminalManager` instances from every open window (`AppState.allTerminalManagers`) and calls `killAllPTYs()` on each concurrently via a `TaskGroup`; returns `.terminateLater` until all PTYs are confirmed dead, then calls `NSApp.replyToApplicationShouldTerminate(true)`.
  3. **Flush** — calls `PersistenceService.flushLayout()` and `PersistenceService.saveWindows(appState.collectDescriptors())` in `applicationWillTerminate`.
- **`SputnikMenuBarController`** (`@MainActor`, `2.6 App Lifecycle/SputnikMenuBarController.swift`) — creates and holds an `NSStatusItem` displaying a monochrome Sputnik satellite template image in the macOS menu bar. Observes `AppState.isProcessing` (now a computed property that is `true` if *any* window is processing) via `withObservationTracking`; applies a `CABasicAnimation` spin to the button's `CALayer` when `true`. Uses `[weak self]` in the observation change handler.
- **About window scene** — `Window("About Sputnik", id: "about")`; fixed size; `.handlesExternalEvents(matching: [])` ensures single instance.
- **`WindowRestorerView`** — SwiftUI helper view (invisible, `frame(width: 0, height: 0)`) attached via `.background { … }` to the first `ContentView`. On its first `task`, it reads `appState.pendingWindowIDs` and calls `openWindow(id: "main", value:)` for each, opening additional windows restored from persistence.
- **`ProcessMonitor` wiring** — singleton created at app launch alongside `AppState`; injected via `.environment(processMonitor)`.
- **No `NSWindowController` subclass** — window behaviour is configured in `AppDelegate.applicationDidFinishLaunching` via the first `NSApp.windows` reference.
- **`@MainActor` boundary** — `AppDelegate` methods are called on the main thread by AppKit; mark `AppDelegate` as `@MainActor` to satisfy Swift 6 strict concurrency.
