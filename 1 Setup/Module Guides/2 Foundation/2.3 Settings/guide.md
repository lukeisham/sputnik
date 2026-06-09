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
  │  AI:          Provider [DeepSeek ▾]                         │
  │               Model    [deepseek-chat                 ]      │
  │               API Key  [••••••••••••••••   Show / Clear]      │
  │               Base URL [https://api.deepseek.com       ]      │
  │               ⚠ API key is stored in macOS Keychain.         │
  │               Usage (This Session):                          │
  │               Model: deepseek-chat                           │
  │               Context Window: [████░░░░░░░░] 34.2%           │
  │               Tokens Used: 12,340 tokens                     │
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
  - `SupportingAIProvider` (enum, `Codable Sendable CaseIterable`, `2 Foundation/2.3 Settings/SupportingAIConfiguration.swift`) — `.deepSeek`, `.gemini`, `.local`; each case has a `defaultBaseURL: URL` computed property
  - `SupportingAIConfiguration` (`Codable Sendable Equatable`, `2 Foundation/2.3 Settings/SupportingAIConfiguration.swift`) — `provider: SupportingAIProvider`, `modelName: String`, `baseURL: URL?` (override; `nil` uses provider default); consumed by `SettingsStore.supportingAIConfig`; no API key field (key lives in Keychain only, never in this struct)
  - `ModelCapacity` (enum, `2 Foundation/2.3 Settings/ModelCapacity.swift`) — static `contextWindow(for modelName: String) -> Int?` lookup seeded with Claude, DeepSeek, Gemini, GPT, Llama, and Mistral model families; returns `nil` for unknown models; shared by `SupportingAIMonitor`, `MainAIMonitor`, and the status bar
  - `SupportingAISettingsView` (`2 Foundation/2.3 Settings/SupportingAISettingsView.swift`) — SwiftUI view for the AI settings tab; reads/writes `SettingsStore.supportingAIConfig`; provider picker (DeepSeek / Gemini / Local); model name field; API key read/written through `KeychainService` at interaction time, never cached in memory; base URL override with default-reset; live session metrics section (context window % bar, token count) driven by `AppState.supportingAIUsage`
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
  - `supportingAIConfig: SupportingAIConfiguration` — provider, model name, and optional base URL override; persisted via `PersistenceService`; API key read/written via `KeychainService` at call time, never cached in `SettingsStore` (resolves ISS-014); the Supporting AI is the app's built-in AI service for resource features — distinct from the Main AI (user-loaded in terminal)
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
