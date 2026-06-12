---
module: 2.5 Foundation – Persistence
status: active
last_updated: 2026-06-12
last_verified: 2026-06-12
open_issues: none
---

## Purpose
Single entry point for all durable data — app settings, layout state, and editor crash-recovery cache — so no module reads or writes storage directly.

## Source Files
| File | Responsibility |
|---|---|
| `PersistenceService.swift` | `@MainActor` protocol — `restore`, `flushLayout`, `restoreWindows`, `saveWindows`, `writeRecovery`, `clearRecovery`, `saveSetting`, `loadSetting`, `saveScratchpad`, `loadScratchpadText`, `saveScratchpadDockedWidth`, `loadScratchpadDockedWidth` |
| `FilePersistenceService.swift` | `@MainActor` class — concrete implementation; reads/writes `UserDefaults`, `layout.json`, `recovery/` |
| `SettingsLoader.swift` | `@MainActor` — key-by-key `Codable` decode with per-key fallback (ISS-051 resolved) |
| `LayoutState.swift` | `Codable Sendable` struct — root persisted blob: `dynamicLayout`, `terminalVisible`, `recentFiles`, `openDocumentURLs`, `activeDocumentURL`; backward-compatible decode |
| `WindowDescriptor.swift` | `Codable Sendable` struct — per-window snapshot for multi-window persistence |

## Technical Summary

- **`PersistenceService`** — `@MainActor` protocol registered in Foundation (SR-1). All modules call the protocol; they never touch `UserDefaults` or `FileManager` directly.
- **`FilePersistenceService`** — `@MainActor` concrete class implementing `PersistenceService`. Reads/writes `UserDefaults` (settings), `layout.json` (layout), `recovery/` (crash recovery).
- **`SettingsLoader`** — `@MainActor`; extracted from `SettingsStore` (ISS-051 resolved); handles key-by-key `Codable` decode with per-key fallback to defaults.
- **`LayoutState`** — root `Codable` struct for `layout.json`; contains `dynamicLayout: DynamicPanelLayout` (replaces old `PanelLayout` + visibility dictionary). Backward-compatible decode with safe defaults (SR-2 — old-schema `layout.json` files without `dynamicLayout` key fall back to `.default`).
- **`WindowDescriptor`** — `Codable` per-window snapshot for multi-window persistence.
- **Scratchpad** — `scratchpadText` and `scratchpadDockedWidth` stored via `PersistenceService` (F-6). `scratchpadFrame` (floating overlay position) has been removed — scratchpad is now always docked.
- **UserDefaults keys:** `scratchpadText`, `scratchpadDockedWidth` (no `scratchpadFrame`).
- **No third-party libraries** — `Foundation` + `Codable` only (SR-5).
- **Threading** — `PersistenceService` is `@MainActor`; file writes dispatched with `Task(priority: .utility)` (SR-4).

## Invariants
- `PersistenceService` is `@MainActor` — all storage reads/writes happen on the main actor; file writes for crash recovery are dispatched with `Task(priority: .utility)` (SR-4)
- No module calls `UserDefaults` or `FileManager` directly — all persistence goes through the `PersistenceService` protocol (SR-1)
- `LayoutState` decodes with safe defaults for fields added after the original schema — older `layout.json` files are never rejected (SR-2)
- `dynamicLayout` falls back to `.default` when absent from `layout.json` (old schema compatibility)
- `SettingsLoader` handles per-key `Codable` decode with per-key fallback — one corrupt key does not poison the entire settings load (ISS-051 resolved)
- API key is never persisted via `PersistenceService` — it lives in the macOS Keychain only (ISS-014)

## Appearance / Function Diagram

```
[Any Module]
     │
     ▼
PersistenceService (protocol, @MainActor singleton in Foundation)
     │
     ├──▶ UserDefaults          — lightweight key/value (theme, font size,
     │                            spelling prefs, window flags,
     │                            scratchpadText, scratchpadDockedWidth)
     │
     └──▶ ~/Library/Application Support/Sputnik/
               ├── layout.json  — DynamicPanelLayout (columns, widths, tabs),
               │                  terminalVisible, recentFiles, openDocumentURLs
               └── recovery/    — editor crash-recovery temp files
                     └── <filename>.recovery

App Launch
     └──▶ PersistenceService.restore()
               checks recovery/ for unclean shutdown → offers recovery dialog
```
