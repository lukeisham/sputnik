---
module: 3.6 JSON Language
status: active
last_updated: 2026-06-15
last_verified: 2026-06-15
open_issues:
---

## Purpose
Adds JSON-specific editing intelligence to the base text editor — debounced inline ghost-text key/value suggestions, real-time syntax validation with an error banner, and a "Render as JSON" command that opens Module 8's JSON viewer panel.

## Diagram

```
  File opened in NSTextView (3.1)
           │
           ▼
  modeForFileType(.json) → EditorMode.json
  sets jsonModeActive = true
           │
           ├─── Keypress path ──────────────────────────────┐
           │                                                │
           ▼                                                │
  DebounceTimer (async Task sleep)                         │
           │  typing paused                                 │
           ▼                                                │
  JSONLanguageProvider                                      │
  ┌─────────────────────────────────┐                       │
  │  detect cursor context          │                       │
  │  (key position vs value pos.)   │                       │
  │  return ghost-text string       │                       │
  └─────────────────────────────────┘                       │
           │  suggestion string                             │
           ▼                                                │
  GhostTextOverlay (greyed text after cursor, 3.1)         │
           │  Tab / Esc                                     │
           ▼                                                │
  Accept → insert   Dismiss → clear                        │
                                                            │
           ├─── Validation path ────────────────────────────┤
           │                                                │
           ▼                                                │
  JSONValidator                                            │
  ┌─────────────────────────────────┐                       │
  │  Task(priority: .utility)       │                       │
  │  JSONSerialization.jsonObject() │                       │
  │  success → clear error banner   │                       │
  │  failure → error banner         │                       │
  │            + underline at offset│                       │
  └─────────────────────────────────┘                       │
                                                            │
           └─── "Render as JSON" command path ──────────────┘
                Edit > Render as... > JSON  (⌃⌘J)
                ▼
  Foundation inter-panel router (2.1)
                ▼
  Module 8 HTMLPreviewPanel (JSON branch) opens
```

## Source Files

| File | Responsibility |
|---|---|
| `JSONLanguageProvider.swift` | `@MainActor` — detects cursor context; returns ghost-text key/value suggestions; debounced via `DebounceTimer`; gated by `jsonModeActive` + `SettingsStore.jsonAutoCompleteEnabled` |
| `JSONValidator.swift` | `@MainActor` — validates document text via `JSONSerialization` on a background Task; writes error info to `EditorViewModel`; gated by `jsonModeActive` + `SettingsStore.jsonValidationEnabled` |
| `ShowJSONViewerCommand.swift` | `@MainActor` — handles "Render as JSON" (`⌃⌘J`) via `InterPanelRouter.open(url)`; mirrors `RenderAsHTMLCommand` in 3.4 |

## Technical Summary

- **Framework(s):** Foundation (`JSONSerialization`), AppKit (`NSTextStorage`)
- **Key types:**
  - `JSONLanguageProvider` — `@MainActor` class; inspects the text before the cursor to determine whether it is in a key position (inside `"…":`) or a value position; returns a completion string (e.g. `""` for an empty string value, `{}` for an object, `[]` for an array); only invoked when `jsonModeActive` is `true` and `SettingsStore.jsonAutoCompleteEnabled` is `true`; uses `DebounceTimer` (2.7) with `SettingsStore.jsonDebounceInterval`
  - `JSONValidator` — `@MainActor` class; called from `EditorViewModel` on every text change (debounced); runs `JSONSerialization.jsonObject(with:options: .fragmentsAllowed)` on a `Task(priority: .utility)`; on error extracts character offset from `NSError.userInfo[NSDebugDescriptionErrorKey]` and calls `EditorViewModel.setValidationErrors(_:)` to surface an error banner and underline; clears errors when JSON is valid; gated by `jsonModeActive` and `SettingsStore.jsonValidationEnabled`
  - `ShowJSONViewerCommand` — `@MainActor` class; conforms to `EditorCommandHandling`; calls `InterPanelRouter.open(url)` with the active file URL; enabled only when `jsonModeActive` is `true`; mirrors `RenderAsHTMLCommand` (3.4)
- **Threading model:** Suggestion generation (`JSONLanguageProvider`) runs on a `Task(priority: .utility)` then returns to `@MainActor` to update the ghost-text overlay. Validation (`JSONValidator`) runs the parse step on `Task(priority: .utility)`; UI updates (error banner) dispatch back to `@MainActor`. `ShowJSONViewerCommand` is synchronous and `@MainActor`.
- **Data flow:**
  - *Activation:* file open → `EditorViewModel.modeForFileType(.json)` → `jsonModeActive = true` → enables suggestions, validation, and "Render as JSON"
  - *Suggestions:* keypress → debounce → `JSONLanguageProvider.suggest(at: cursorRange)` → `GhostTextOverlay.show(_:)` → Tab accepts / Esc dismisses
  - *Validation:* text change → debounce → `JSONValidator.validate(text:)` → error banner on/off → underline at error offset
  - *Viewer:* Edit > Render as... > JSON (`⌃⌘J`) → `ShowJSONViewerCommand` → `InterPanelRouter.open(url)` → Module 8 panel opens in JSON viewer mode
- **State owned:** `jsonModeActive` flag (owned by `EditorViewModel` in 3.1); current ghost-text suggestion string (in-memory, discarded on dismiss)
- **Dependencies:** 3.1 Text — `NSTextView` delegate chain, `NSTextStorage` access, `GhostTextOverlay`, `EditorViewModel`; Foundation 2.7 — `DebounceTimer`; Foundation 2.1 — `InterPanelRouter`; Foundation 2.3 — `SettingsStore` (toggle + debounce interval); Module 8 — target panel for render command
- **Failure modes:** Non-JSON text in `.json` file → `JSONValidator` reports syntax error; `JSONLanguageProvider` degrades gracefully (returns nil when cursor context is unclear); "Render as JSON" while Module 8 already open → brings existing panel to front; parse step on very large file → `JSONSerialization` is O(n) but bounded by module 3's `EncodingGuard` size limit (10 MB by default)

## Invariants

- This sub-module **never imports module 8 or 9 directly** — all cross-module calls go through Foundation 2.1 (`InterPanelRouter`) and Foundation 2.3 (`SettingsStore`) (SR-1)
- `JSONValidator` runs JSON parsing **off the main thread** via `Task(priority: .utility)` — never blocks the UI (SR-4)
- All UI updates (error banner, ghost text) happen on `@MainActor` (SW-1)
- `jsonModeActive` is owned exclusively by `EditorViewModel` (3.1) — sub-module files read it, never set it (SR-1)
- Both `JSONLanguageProvider` and `JSONValidator` are **no-ops** when `jsonModeActive` is `false` — they activate only for `.json` files
