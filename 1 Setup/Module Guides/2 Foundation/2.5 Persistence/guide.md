---
module: 2.5 Foundation – Persistence
status: draft
---

## Purpose
Single entry point for all durable data — app settings, layout state, and editor crash-recovery cache — so no module reads or writes storage directly.

## Appearance / Function Diagram

```
[Any Module]
     │
     ▼
PersistenceService (protocol, @MainActor singleton in Foundation)
     │
     ├──▶ UserDefaults          — lightweight key/value (theme, font size,
     │                            spelling prefs, window flags)
     │
     └──▶ ~/Library/Application Support/Sputnik/
               ├── layout.json  — panel sizes, visibility, last open file
               └── recovery/    — editor crash-recovery temp files
                     └── <filename>.recovery

App Launch
     └──▶ PersistenceService.restore()
               checks recovery/ for unclean shutdown → offers recovery dialog
```

## Technical Summary

- **`PersistenceService`** — `@MainActor` class exposed via a protocol registered in Foundation (SR-1). All modules call the protocol; they never touch `UserDefaults` or `FileManager` directly.
- **UserDefaults** — app-level settings only (theme, font size, panel toggle defaults, spelling preferences). No file paths or mutable state here.
- **`~/Library/Application Support/Sputnik/`** — obtained once via `FileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)`. Layout state and crash-recovery files live here.
- **Layout state** — a `Codable` struct (`LayoutState`) serialised to `layout.json` on every panel resize or toggle. Read on launch to restore the last window arrangement.
- **Crash recovery** — the Text Editor Window (module 3) calls `PersistenceService.writeRecovery(for:content:)` on every significant edit. On launch, `restore()` scans `recovery/` and surfaces a recovery dialog if any file was not cleanly closed.
- **No third-party libraries** — `Foundation` + `Codable` only (SR-5).
- **Threading** — `PersistenceService` is `@MainActor`; file writes for crash recovery are dispatched with `Task(priority: .utility)` so they never block the editor.
