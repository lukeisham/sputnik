---
module: 2.3 Foundation – Settings
status: draft
last_updated: 2026-06-07
---

## Purpose
Own all user-configurable preferences — appearance, editor behaviour, and spelling/grammar — and expose them as a single observable store so every module reads the same values without touching storage directly.

## Diagram

```
  macOS Settings Window  (SwiftUI Settings scene)
  ┌───────────────────────────────────────────┐
  │  [Appearance]  [Editor]  [Grammar]        │
  │                                           │
  │  Appearance:  theme ● light ○ dark ○ auto │
  │               font  [SF Mono     ▾] 13pt  │
  │                                           │
  │  Editor:      auto-save  [on ▾]           │
  │               line numbers  [✓]           │
  │               word wrap     [✓]           │
  │                                           │
  │  Grammar:     spell check   [✓]           │
  │               grammar check [✓]           │
  └───────────────┬───────────────────────────┘
                  │ writes
                  ▼
           SettingsStore  (@Observable @MainActor)
                  │ persists via
                  ▼
           PersistenceService (2.5) → UserDefaults
                  │ observed by
                  ├──▶ Text Editor (3)   — font, line numbers, wrap, spell/grammar
                  ├──▶ Markdown Preview (4) — theme
                  ├──▶ HTML Preview (8)  — theme
                  ├──▶ PDF Viewer (5)    — theme
                  ├──▶ File Tree (6)     — theme, font
                  └──▶ Terminal (7)      — font, theme
```

## Technical Summary
- **Framework(s):** SwiftUI (`@Observable`, `Settings` scene), Foundation
- **Key types:**
  - `SettingsStore` — `@Observable @MainActor` class; single instance created at app launch alongside `AppState` and injected via `.environment(settingsStore)` <!-- assumed -->
  - `AppTheme` — enum: `.light`, `.dark`, `.system` <!-- assumed -->
  - `EditorFont` — struct wrapping `NSFont` name and point size <!-- assumed -->
- **Threading model:** `SettingsStore` is `@MainActor`. All property changes are on the main thread; `PersistenceService` writes are dispatched with `Task(priority: .utility)` so UI is never blocked by a `UserDefaults` write.
- **Data flow:** User changes a setting in the Settings window → `SettingsStore` property updates → `@Observable` propagates the change to any view observing it → `PersistenceService` persists the new value asynchronously.
- **State owned:**
  - `theme: AppTheme`
  - `editorFont: EditorFont`
  - `autoSaveEnabled: Bool`
  - `lineNumbersEnabled: Bool`
  - `wordWrapEnabled: Bool`
  - `spellCheckEnabled: Bool`
  - `grammarCheckEnabled: Bool`
- **Dependencies:** `PersistenceService` (2.5) for read/write to `UserDefaults`. No other module dependencies.
- **Failure modes:**
  - `UserDefaults` returns nil on first launch → `SettingsStore` falls back to hardcoded defaults; no crash.
  - Corrupt preferences key → caught by `Codable` decode failure → default value used; corrupt key is overwritten on next save.

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  3. Settings
    4. Determins the appearance and behavior of the app, plus spelling and grammar checking settings
```
