---
module: 2.3 Settings
status: active
last_updated: 2026-09-28
last_verified: 2026-06-16
---

## Purpose

Provides the app-wide settings window where users configure appearance, editor behaviour, Apple's spelling and grammar checker, terminal styling, the Supporting AI provider, templates, and a keyboard shortcuts reference.

---

## Diagram

The settings window is a tabbed panel with seven sections. Opened via the Sputnik menu or ⌘,.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  [Appearance] [Editor] [Spelling & Grammar] [Terminal] [AI] [Templates] [Shortcuts] │  ← tab bar
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─── Appearance ──────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  Theme         [ Light | Dark | System ]                │ │  ← segmented
│  │  ───────────────────────────────────────────────────────│ │
│  │  Editor Font   [ Font Name          ] [ Size ]          │ │
│  │  ───────────────────────────────────────────────────────│ │
│  │  Per-Panel Overrides                                    │ │
│  │  ▼ Text Editor                                          │ │  ← disclosure
│  │     Font       [ Font Name          ] [ Size ]          │ │
│  │     Background [ ■■■■■■■■■■■■■■■■■■ ]                   │ │  ← color picker
│  │     [Clear Override]                                    │ │
│  │  ▼ Markdown Preview                                     │ │
│  │     Font       [ Font Name          ] [ Size ]          │ │
│  │     Background [ ■■■■■■■■■■■■■■■■■■ ]                   │ │
│  │     [Clear Override]                                    │ │
│  │  ▼ HTML Preview                                         │ │
│  │     Font       [ Font Name          ] [ Size ]          │ │
│  │     Background [ ■■■■■■■■■■■■■■■■■■ ]                   │ │
│  │     [Clear Override]                                    │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─── Editor ──────────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  ☑ Auto-save                                            │ │
│  │  ☑ Line numbers                                         │ │
│  │  ☑ Word wrap                                            │ │
│  │  ☑ Code block highlighting                              │ │
│  │  ☑ HTML syntax checking                                 │ │
│  │  ☑ Vertical indent lines                                │ │
│  │  ───────────────────────────────────────────────────────│ │
│  │  Max file size     [ 50 ] MB                            │ │
│  │  ASCII trigger key [ _ ]                                │ │
│  │  ───────────────────────────────────────────────────────│ │
│  │  Auto-complete (ghost text) 'debounce' delay            │ │
│  │  Markdown  [ 0.5s ▼ ]                                   │ │  ← dropdown
│  │  ASCII     [ 0.5s ▼ ]                                   │ │
│  │  HTML      [ 0.5s ▼ ]                                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─── Spelling & Grammar ──────────────────────────────────┐ │
│  │                                                         │ │
│  │  ☑ Check spelling while typing                          │ │
│  │  ☐ Check grammar with spelling                          │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─── Terminal ────────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  Font       [ Menlo              ] [ 12 ]               │ │
│  │  Scrollback [ 10000              ] lines                │ │
│  │  ───────────────────────────────────────────────────────│ │
│  │  Foreground [ ■■■■■■■■■■■■■■■■■■ ]                      │ │  ← color picker
│  │  Background [ ■■■■■■■■■■■■■■■■■■ ]                      │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─── Support AI ───────────────────────────────────────────┐│
│  │                                                          ││
│  │  Provider  [ DeepSeek  ▼ ]                               ││  ← picker
│  │  Model     [ deepseek-chat                    ]          ││
│  │  API Key   [ ••••••••••••••••• ] [Show] [Clear]          ││  ← Keychain
│  │            ✔ Key is stored in Keychain.                  ││
│  │  Base URL  [                                ] [Default]  ││
│  │            Leave empty for provider default.             ││
│  │  [Save]    Your API key is stored securely in the…       ││
│  │  ─────────────────────────────────────────────────────── ││
│  │  Usage (This Session)                                    ││
│  │  Model               deepseek-chat                       ││
│  │  Context Window      [████████░░░░] 42.5%                ││  ← progress
│  │  Tokens Used         1,234 tokens                        ││
│  └──────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─── Shortcuts ───────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  (read-only reference table of every keyboard shortcut  │ │
│  │   grouped by menu: Sputnik, File, Edit, Terminal,       │ │
│  │   Format, View, Help)                                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─── Templates ───────────────────────────────────────────┐ │
│  │                                                         │ │
│  │  Template Folder                                        │ │
│  │  ┌──────────────────────────────────┐  [Choose…]       │ │
│  │  │ ~/Library/…/Sputnik/Templates    │                  │ │
│  │  └──────────────────────────────────┘                  │ │
│  │  [Reset to Default]                                     │ │
│  │  Templates are saved and loaded from this folder.       │ │
│  │  Changes take effect immediately.                       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ◄  When you switch tabs, the form below swaps entirely.     │
│     All seven tabs share the same window frame.                │
└──────────────────────────────────────────────────────────────┘
```

## Source Files

| File | Responsibility |
|---|---|
| `SettingsView.swift` | TabView container — hosts all seven setting tabs, 460 pt wide |
| `AppearanceTab.swift` | Theme, Editor Font, Per-Panel Override disclosure groups (Text Editor / Markdown Preview / HTML Preview) |
| `EditorTab.swift` | Toggles (auto-save, line numbers, word wrap, code block highlighting, HTML syntax check, vertical indent lines), max file size, ASCII trigger key, auto-complete delay pickers |
| `SpellingTab.swift` | Two toggles for Apple's checker: "Check spelling while typing" (`systemSpellCheckEnabled`) and "Check grammar with spelling" (`systemGrammarCheckEnabled`). The language follows the macOS system setting. |
| `TerminalTab.swift` | Font name/size, scrollback line count, foreground/background color pickers |
| `SupportingAISettingsView.swift` | Provider selector, model name, Keychain-backed API key, base URL override, Save button, session usage metrics |
| `TemplatesTab.swift` | Template folder path display, "Choose…" (`NSOpenPanel`, directory picker), "Reset to Default" button; calls `settings.setTemplateDirectoryURL(_:)` and `appState.applyTemplateDirectory(_:)` |
| `ShortcutsTab.swift` | Read-only reference table listing every keyboard shortcut grouped by menu (Sputnik, File, Edit, Terminal, Format, View, Help); reads from `KeyboardShortcutCatalog` |

## Technical Summary

- **Framework:** SwiftUI (TabView, Form, DisclosureGroup, ColorPicker, LabeledContent, Picker, SecureField)
- **Key type:** `SettingsStore` (Foundation 2.3) — the single source of truth consumed by all seven tabs; all mutations go through `settings.set*(...)` methods that persist to `UserDefaults` via `SettingsPersistence`
- **Window:** Standard macOS Settings scene (`Settings { SettingsView() }` in `SputnikApp.swift`), opened via Sputnik menu or ⌘,
- **Threading:** All UI updates on `@MainActor`; settings are loaded synchronously at app launch via `SettingsLoader` and held for the app lifetime
- **Dependencies:** `FoundationModule` (SputnikColor, SputnikFont, SputnikSpacing, SettingsStore, AutoCompleteDebounceStep, DebounceStepPicker, SupportingAIConfiguration), `KeychainService` (for API key storage)

## Templates setting (added 2026-06-16)

- `templateDirectoryURL: URL?` on `SettingsStore` — `nil` = use default `~/Library/Application Support/Sputnik/Templates/`. Persisted as an absolute path string under key `"sputnik.settings.templateDirectoryURL"`.
- `setTemplateDirectoryURL(_ value: URL?)` mutator — persists and triggers `AppState.applyTemplateDirectory(_:)` from `TemplatesTab`.
- Loaded by `SettingsLoader` on init; falls back to `nil` (default path) if the key is absent.

## Invariants

- `CaseIterable` on `WritingAssistLanguage` and `WritingAssistFunction` is used by the Settings UI to enumerate toggle rows
- The **Writing Assistance** per-language toggle matrix is NOT in this settings window — it lives in the **Edit → Writing Assistance** menu instead (and the **Help → Interaction** submenu for Interaction toggles)
- The **Spelling & Grammar** tab controls Apple's `NSTextView` checker (`isContinuousSpellCheckingEnabled` / `isGrammarCheckingEnabled`), not Apple Intelligence. Apple Intelligence Writing Tools are turned on independently via `writingToolsBehavior = .complete` in module 3.1
- `systemSpellCheckEnabled` (default `true`) and `systemGrammarCheckEnabled` (default `false`) are stored `Bool`s under the old keys `sputnik.settings.spellCheck` and `sputnik.settings.grammarCheck`, so each user's old on/off choice stays. They are not part of `WritingAssistMatrix`
- `WritingAssistMatrix` has no spelling or grammar language and no Instant Correct function. Old matrix JSON that has these keys decodes without error, and the old keys are ignored
- All seven tabs share a single `SettingsStore` instance injected via `.environment(settingsStore)` at the app level
- The AI tab configures the **Supporting AI** (Sputnik's own helper for help lookups/completions), not Apple Intelligence — uses third-party providers (DeepSeek, Gemini, Local) with Keychain-backed API keys
