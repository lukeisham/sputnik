---
module: 2.5 Persistence
status: stable
last_updated: 2026-09-28
last_verified: 2026-06-14
open_issues: none
---

## Purpose
Provides the serialisation contract (`PersistenceService` protocol) and concrete implementation (`FilePersistenceService`) for all durable state: global `layout.json`, per-window `windows.json`, crash recovery cache, settings via `UserDefaults`, and scratchpad state.

## Diagram

```
                  ┌───────────────────────────────────────┐
                  │          PersistenceService            │
                  │  (protocol, @MainActor)                │
                  │                                       │
                  │  restore()          → LayoutState      │
                  │  flushLayout(_:)                       │
                  │  restoreWindows()   → [WindowDescriptor]│
                  │  saveWindows(_:)                       │
                  │  writeRecovery(for:content:)           │
                  │  clearRecovery(for:)                   │
                  │  pendingRecoveryNames() → [String]     │
                  │  saveSetting<T>(_:forKey:)             │
                  │  loadSetting<T>(forKey:) → T?          │
                  │  saveScratchpad(text:)                 │
                  │  loadScratchpadText() → String         │
                  │  saveScratchpadDockedWidth(_:)         │
                  │  loadScratchpadDockedWidth() → CGFloat │
                  └──────────────┬────────────────────────┘
                                 │
                  ┌──────────────▼────────────────────────┐
                  │        FilePersistenceService          │
                  │  (concrete, @MainActor)                │
                  │                                       │
                  │  supportDirectory =                    │
                  │    ~/Library/Application Support/      │
                  │    Sputnik/                            │
                  │    ├── layout.json                     │
                  │    ├── windows.json                    │
                  │    └── recovery/*.recovery             │
                  │                                       │
                  │  UserDefaults for settings + scratchpad│
                  └───────────────────────────────────────┘

  Launch flow:
  AppDelegate → persistence.restore() → layoutState
              → persistence.restoreWindows() → [WindowDescriptor]
              → AppState.restoreWindows(from: descriptors)
                  └→ WindowState.layout = desc.layout (per-window)

  Quit flow (synchronous — applicationWillTerminate returns immediately):
  AppDelegate.applicationWillTerminate
    → persistence.flushLayoutSync(layoutState)    ← global layout.json (sync)
    → AppState.collectDescriptors()
        └→ WindowDescriptor.layout = ws.layout    ← per-window
    → persistence.saveWindowsSync(descriptors)    ← windows.json (sync)

  Async write path (mid-session saves):
  flushLayout / saveWindows / writeRecovery / clearRecovery
    → PersistenceWriter actor (cooperative thread pool)
        → JSONEncoder().encode / data.write(atomic:) / String.write / removeItem
        → errors logged via os.Logger at .warning / .error
```

## Source Files

| File | Responsibility |
|---|---|
| `PersistenceService.swift` | `@MainActor` protocol defining the full persistence contract, including synchronous flush methods |
| `FilePersistenceService.swift` | Concrete implementation: JSON encode/decode for layout/windows, file I/O via `PersistenceWriter` actor, synchronous quit-time flush, UserDefaults bridge for settings and scratchpad |
| `PersistenceWriter.swift` | `actor` that serialises all file-system writes (`write<T:Encodable>`, `writeText`, `remove`); runs on the cooperative thread pool, never on `@MainActor` |
| `LayoutState.swift` | Top-level persisted blob: `dynamicLayout: DynamicPanelLayout`, `terminalVisible`, `recentFiles`, `openDocumentURLs`, `activeDocumentURL`; backward-compatible Codable decode |
| `WindowDescriptor.swift` | Per-window persisted snapshot: `id`, `workspaceDirectoryURL`, `openTabURLs`, `activeDocumentURL`, `layout: LayoutState`, `windowFrame`, `documentViewStates`; backward-compatible decode |
| `DocumentViewState.swift` | Per-document editor state: caret position (`selectedRange`) and scroll offset; used in `WindowDescriptor.documentViewStates` |
| `SettingsLoader.swift` | Extracted `SettingsStore` deserialisation orchestration (SR-6). Loads the writing-assist matrix as saved (no migration) and the two Apple checker toggles from `sputnik.settings.spellCheck` / `sputnik.settings.grammarCheck` |

## Technical Summary

- **Frameworks:** Foundation (`FileManager`, `Data`, `JSONEncoder`/`JSONDecoder`, `UserDefaults`), `os` (`Logger`), CoreGraphics (`CGRect` for window frame)
- **Threading:** All protocol methods are `@MainActor`. Async file I/O (`flushLayout`, `saveWindows`, `writeRecovery`, `clearRecovery`) dispatches through `PersistenceWriter` — an actor on the cooperative thread pool — so encode + write never touch the main thread and concurrent calls are serialised automatically. Quit-time writes (`flushLayoutSync`, `saveWindowsSync`) run synchronously on `@MainActor` because `applicationWillTerminate` returns before any fire-and-forget Task can be scheduled.
- **Error visibility:** All catch blocks log via `os.Logger` (subsystem `com.sputnik`, category `Persistence`) — `.error` for recovery I/O failures, `.warning` for layout/window failures. Visible in Console.app.
- **Data flow:**
  - **Launch:** `AppDelegate.applicationDidFinishLaunching` → `restore()` for global `layout.json` + `restoreWindows()` for per-window `windows.json` → `AppState.restoreWindows(from:)` creates `WindowState` instances with saved layouts → each `ContentView` reads its `WindowState.layout`
  - **Quit:** `AppDelegate.applicationWillTerminate` → `flushLayoutSync(layoutState)` (synchronous) + `collectDescriptors()` / `saveWindowsSync()` (synchronous)
  - **Settings:** `saveSetting<T>` encodes synchronously on `@MainActor` and calls `UserDefaults.standard.set` directly (O(1), thread-safe). `loadSetting<T>` decodes from `UserDefaults`.
  - **Crash recovery:** `writeRecovery(for:content:)` prepends a `// source: <absolute-path>` header line then writes via `PersistenceWriter`; `pendingRecoveryNames()` reads the header to return the original path (falls back to filename for legacy files without the header); `clearRecovery(for:)` deletes via `PersistenceWriter`.
- **Recovery file naming:** `<display>-<djb2hash>.<extension>` where `<djb2hash>` is a stable 64-bit djb2 hash of the full file path (hex), making files with the same name in different directories produce distinct recovery entries. `String.hashValue` is NOT used — it is randomised per process launch.
- **Dependencies:** `DynamicPanelLayout` (2.4), `DocumentViewState`, `UserDefaults`
- **Failure modes:** Corrupt JSON → decode falls back to `.default` / empty array; missing files → returns defaults; write failure → logged at `.warning`/`.error`; directory creation failure → logged at `.error`, subsequent writes will also fail and be logged

## Invariants

- All async file I/O flows through `PersistenceWriter` actor — never directly from `@MainActor` code
- Quit-time writes use `flushLayoutSync` / `saveWindowsSync` — never the async `flushLayout` / `saveWindows` from `applicationWillTerminate`
- Recovery files are named `<display>-<djb2hash>.recovery` and contain a `// source: <absolute-path>` header as their first line
- `LayoutState.dynamicLayout` falls back to `.default` on decode failure (old schema or corrupt file). A column with an unknown `PanelID` is not a decode failure: `DynamicPanelLayout` drops only that column (see 2.4). The layout falls back to `.default` only when no column decodes
- `WindowDescriptor` fields added after the original schema decode with safe defaults (e.g. `windowFrame` → `nil`, `documentViewStates` → `[:]`)
- Scratchpad state (text + docked width) is stored in `UserDefaults`, not in `layout.json`/`windows.json`
- Settings keys use `UserDefaults` with `Data`-encoded JSON values, written synchronously on `@MainActor`
- All write failures are logged via `os.Logger` — no silent error swallowing

### Global-vs-Per-Window Precedence Rule

Two persistence channels touch `DynamicPanelLayout`:

1. **Global `layout.json`** — written by `AppDelegate.applicationWillTerminate` via `flushLayout(layoutState)`. The `layoutState` property is loaded at launch and never updated during the session, so this file carries stale data. It exists for backward compatibility only.

2. **Per-window `windows.json`** — written by `AppState.collectDescriptors()` / `saveWindows()`. Each `WindowDescriptor` contains a full `LayoutState` with the live `DynamicPanelLayout` including per-column widths and render modes.

**Precedence on launch:**
- Restored windows (from `windows.json`) use their own `desc.layout` — widths, column order, render modes are restored exactly as saved.
- Brand-new windows (no matching descriptor) use the default `WindowState()` initialiser which creates `DynamicPanelLayout.default`.
- The global `layout.json` is NOT used to initialise any window's layout at launch; it is only written on quit for backward compatibility.

**User impact:** Closing and reopening a window restores that window's exact column widths, order, and render modes. Per-window layouts do not bleed into each other.
