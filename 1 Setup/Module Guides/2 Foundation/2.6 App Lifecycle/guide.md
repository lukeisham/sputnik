---
module: 2.6 Foundation – App Lifecycle
status: draft
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
     │        │
     │        ├── applicationShouldTerminate      → TerminalManager.killAllPTYs()
     │        │                                    → returns .terminateLater until clean
     │        │
     │        └── applicationWillTerminate        → PersistenceService.flushLayout()
     │
     └── WindowGroup (body)
              └── ContentView                     ← root SwiftUI layout (all panels)
                       └── .handlesExternalEvents  ← single-window enforcement
```

## Technical Summary

- **`@main struct SputnikApp: App`** — entry point. Declares the `WindowGroup` and attaches `AppDelegate` via `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`.
- **`AppDelegate`** — `NSObject` + `NSApplicationDelegate`. Does not own any views. Three responsibilities only:
  1. **Launch** — calls `PersistenceService.restore()` and surfaces crash-recovery dialog if needed.
  2. **Termination gate** — calls `TerminalManager.killAllPTYs()`; returns `.terminateLater` until the PTY is confirmed dead, then calls `NSApp.replyToApplicationShouldTerminate(true)`.
  3. **Flush** — calls `PersistenceService.flushLayout()` in `applicationWillTerminate`.
- **`NSWindow` reference** — obtained once in `AppDelegate` via `NSApp.windows.first` after launch and stored as `weak var mainWindow: NSWindow?`. Used by Foundation UI layer for panel layout restoration and custom toolbar config. Never held strongly.
- **Single window enforcement** — `WindowGroup` body uses `.handlesExternalEvents(matching:)` to prevent a second window opening when the user double-clicks a file in Finder; file opens are routed through `PersistenceService` and the inter-panel communication layer (module 2.1) instead.
- **No `NSWindowController` subclass** — window behaviour (title, style mask, min size) is configured in `AppDelegate.applicationDidFinishLaunching` via the `mainWindow` reference, not through a custom controller subclass.
- **`@MainActor` boundary** — `AppDelegate` methods are called on the main thread by AppKit; mark `AppDelegate` as `@MainActor` to satisfy Swift 6 strict concurrency and avoid actor-crossing warnings when calling `PersistenceService`.
