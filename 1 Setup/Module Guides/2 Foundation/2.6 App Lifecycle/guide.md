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
     │        ├── applicationShouldTerminate      → TerminalManager.killAllPTYs()
     │        │                                    → returns .terminateLater until clean
     │        │
     │        └── applicationWillTerminate        → processMonitor.stop()
     │                                              → PersistenceService.flushLayout()
     │
     └── App body (scenes)
              ├── WindowGroup (main)
              │        └── ContentView                    ← root SwiftUI layout (all panels)
              │                 └── .handlesExternalEvents ← single-window enforcement
              └── Window("About Sputnik", id: "about")
                       └── AboutWindowView               ← fixed size, no resize handle
                                └── .handlesExternalEvents(matching: [])  ← single instance
```

## Technical Summary

- **`@main struct SputnikApp: App`** — entry point. Declares the `WindowGroup`, the `Window("About Sputnik", id: "about")` scene, and attaches `AppDelegate` via `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`.
- **`AppDelegate`** — `NSObject` + `NSApplicationDelegate`. Does not own any views. Four responsibilities:
  1. **Launch** — calls `PersistenceService.restore()`, surfaces crash-recovery dialog if needed, and instantiates `SputnikMenuBarController` (held as a `strong` property for app lifetime).
  2. **Termination gate** — calls `TerminalManager.killAllPTYs()`; returns `.terminateLater` until the PTY is confirmed dead, then calls `NSApp.replyToApplicationShouldTerminate(true)`.
  3. **Flush** — calls `PersistenceService.flushLayout()` in `applicationWillTerminate`.
- **`SputnikMenuBarController`** (`@MainActor`, `2.6 App Lifecycle/SputnikMenuBarController.swift`) — creates and holds an `NSStatusItem` displaying a monochrome Sputnik satellite template image (16×16 @1x, 32×32 @2x) in the macOS menu bar. Observes `AppState.isProcessing` via `withObservationTracking`; applies a `CABasicAnimation` spin to the button's `CALayer` when `true`. Uses `[weak self]` in the observation change handler. `NSStatusItem` creation is guarded — the system can return nil. Template image means AppKit tints it correctly in light/dark mode automatically; no SwiftUI equivalent exists for `NSStatusItem` (AppKit-only use is documented).
- **About window scene** — `Window("About Sputnik", id: "about")` in `SputnikApp.body`; fixed size (no resize handle, no toolbar); `.handlesExternalEvents(matching: [])` ensures a second activation brings the existing window to front rather than opening a duplicate. Opened via `openWindow(id: "about")` from `SputnikCommands`.
- **`ProcessMonitor` wiring** — `ProcessMonitor` singleton is created at app launch alongside `AppState`; `AppDelegate.applicationDidFinishLaunching` calls `processMonitor.start()`; `applicationWillTerminate` calls `processMonitor.stop()`. The instance is injected into the SwiftUI environment via `.environment(processMonitor)` so `StatusBarView` (2.4) can read `ramMB` and `cpuPercent` without directly importing the utilities module.
- **`NSWindow` reference** — obtained once in `AppDelegate` via `NSApp.windows.first` after launch and stored as `weak var mainWindow: NSWindow?`. Used by Foundation UI layer for panel layout restoration and custom toolbar config. Never held strongly.
- **Single window enforcement** — `WindowGroup` body uses `.handlesExternalEvents(matching:)` to prevent a second window opening when the user double-clicks a file in Finder; file opens are routed through `PersistenceService` and the inter-panel communication layer (module 2.1) instead.
- **No `NSWindowController` subclass** — window behaviour (title, style mask, min size) is configured in `AppDelegate.applicationDidFinishLaunching` via the `mainWindow` reference, not through a custom controller subclass.
- **`@MainActor` boundary** — `AppDelegate` methods are called on the main thread by AppKit; mark `AppDelegate` as `@MainActor` to satisfy Swift 6 strict concurrency and avoid actor-crossing warnings when calling `PersistenceService`.
