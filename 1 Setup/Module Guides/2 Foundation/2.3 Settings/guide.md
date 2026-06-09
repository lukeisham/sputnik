---
module: 2.3 Foundation – Settings
status: active
last_updated: 2026-06-09
---

## Purpose
Own all user-configurable preferences — appearance, editor behaviour, and spelling/grammar — and expose them as a single observable store so every module reads the same values without touching storage directly.

## Diagram

```
  macOS Settings Window  (SwiftUI Settings scene)
  ┌───────────────────────────────────────────────────────────────┐
  │  [Appearance]  [Editor]  [Grammar]  [Terminal]  [AI]          │
  │                                                               │
  │  Appearance:  theme ● light ○ dark ○ auto                     │
  │               font  [SF Mono     ▾] 13pt                      │
  │               ┌───────────────────────────────────────────┐   │
  │               │ Per-Panel Overrides                       │   │
  │               │ ▸ Text Editor      font · bg colour well  │   │
  │               │ ▸ Markdown Preview font · bg colour well  │   │
  │               │ ▸ HTML Preview     font · bg colour well  │   │
  │               └───────────────────────────────────────────┘   │
  │                                                               │
  │  Editor:      auto-save  [on ▾]                               │
  │               line numbers  [✓]                               │
  │               word wrap     [✓]                               │
  │                                                               │
  │  Grammar:     spell check   [✓]                               │
  │               grammar check [✓]                               │
  │                                                               │
  │  AI:          Model    [claude-sonnet-4-6              ]      │
  │               API Key  [••••••••••••••••   Show / Clear]      │
  │               Base URL [https://api.anthropic.com      ]      │
  │               ⚠ API key is stored in macOS Keychain.         │
  └───────────────┬───────────────────────────────────────────────┘
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
  - `EditorFont` — struct wrapping PostScript font name and point size <!-- assumed -->
  - `TerminalColor` — lightweight RGBA struct, `Codable`; extracted from module 7 so Foundation owns it without importing Terminal
  - `AIConfiguration` (`Sendable Codable`, `2 Foundation/2.3 Settings/AIConfiguration.swift`) — `modelName: String`, `baseURL: URL?`; no API key field (key lives in Keychain only, never in this struct); consumed by `SettingsStore.aiConfig`, the status bar (F-5), and any future AI-calling feature
  - `ModelCapacity` (enum, `2 Foundation/2.3 Settings/ModelCapacity.swift`) — static `contextWindow(for modelName: String) -> Int?` lookup seeded with the current Claude model family; returns `nil` for unknown models; shared by F-5 context-% display and F-8 terminal model detection
  - `AISettingsView` (`2 Foundation/2.3 Settings/AISettingsView.swift`) — SwiftUI view for the AI settings tab; reads/writes `SettingsStore.aiConfig`; API key read/written through `KeychainService` at interaction time, never cached in memory
  - `WritingAssistMatrix` — `Codable Sendable` struct; stores one `Bool` per applicable `WritingAssistFunction × WritingAssistLanguage` cell; non-applicable cells always return `false`; resolves ISS-011
  - `WritingAssistLanguage` — enum: `.spelling`, `.grammar`, `.markdown`, `.html`, `.asciiArt`
  - `WritingAssistFunction` — enum: `.instantCorrect`, `.autoComplete`, `.moreContext`
- **Threading model:** `SettingsStore` is `@MainActor`. All property changes are on the main thread; `PersistenceService` writes are dispatched with `Task(priority: .utility)` so UI is never blocked by a `UserDefaults` write.
- **Data flow:** User changes a setting in the Settings window → `SettingsStore` property updates → `@Observable` propagates the change to any view observing it → `PersistenceService` persists the new value asynchronously.
- **State owned:**
  - `theme: AppTheme`
  - `editorFont: EditorFont`
  - `textEditorFont: EditorFont?` — per-panel override; `nil` inherits `editorFont` (F-4)
  - `markdownPreviewFont: EditorFont?` — per-panel override; `nil` inherits `editorFont` (F-4)
  - `htmlPreviewFont: EditorFont?` — per-panel override; `nil` inherits `editorFont` (F-4)
  - `resolvedTextEditorFont: EditorFont` — **computed**: `textEditorFont ?? editorFont` (F-4)
  - `resolvedMarkdownPreviewFont: EditorFont` — **computed**: `markdownPreviewFont ?? editorFont` (F-4)
  - `resolvedHtmlPreviewFont: EditorFont` — **computed**: `htmlPreviewFont ?? editorFont` (F-4)
  - `textEditorBackground: Color` — default: `SputnikColor.editorBackground` (F-4)
  - `markdownPreviewBackground: Color` — default: `SputnikColor.background` (F-4)
  - `htmlPreviewBackground: Color` — default: `SputnikColor.background` (F-4)
  - `aiConfig: AIConfiguration` — model name and optional base URL; persisted via `PersistenceService`; API key read/written via `KeychainService` at call time, never cached in `SettingsStore` (resolves ISS-014)
  - `autoSaveEnabled: Bool`
  - `lineNumbersEnabled: Bool`
  - `wordWrapEnabled: Bool`
  - `writingAssist: WritingAssistMatrix` — the per-language × per-function assist matrix (ISS-011); single source of truth for all writing-assist toggles
  - `spellCheckEnabled: Bool` — **computed** over `writingAssist.isEnabled(.instantCorrect, for: .spelling)`; kept for existing consumers
  - `grammarCheckEnabled: Bool` — **computed** over `writingAssist.isEnabled(.instantCorrect, for: .grammar)`; kept for existing consumers
  - `terminalFontName: String`
  - `terminalFontSize: Double`
  - `terminalScrollbackLimit: Int`
  - `terminalForeground: TerminalColor`
  - `terminalBackground: TerminalColor`
  - `editorMaxFileSizeBytes: Int`
  - `markdownDebounceInterval: TimeInterval`
  - `asciiDebounceInterval: TimeInterval`
  - `htmlDebounceInterval: TimeInterval`
  - `spellCheckDebounceInterval: TimeInterval`
  - `asciiTriggerKey: String`
  - `spellCheckLocale: String?`
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
