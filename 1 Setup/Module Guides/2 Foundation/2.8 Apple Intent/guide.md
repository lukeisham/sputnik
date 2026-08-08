---
module: 2.8 Apple Intent
status: active
last_updated: 2026-06-15
last_verified: 2026-06-15
open_issues: ISS-XXX (intents are stubs — routing not yet implemented)
---

## Purpose

Lets you control Sputnik with Siri, Shortcuts, and Spotlight — without opening the app manually. Every panel toggle, editor operation, Terminal command, window action, appearance setting, and help lookup is exposed as an `AppIntent`.

## Diagram

```
  Siri / Shortcuts / Spotlight / Apple Intelligence
                       │
                       ▼
  ┌─────────────────────────────────────────────────┐
  │  AppIntents framework  (macOS Ventura+)         │
  └─────────────────────────────────────────────────┘
                       │
      ┌────────────────┼────────────────┐
      ▼                ▼                ▼
  ┌────────┐   ┌──────────────┐   ┌──────────────┐
  │Document│   │  Panel       │   │  Window /    │
  │ Intents│   │  Intents     │   │  App Intents │
  │ (3)    │   │  (8)         │   │  (6)          │
  └────────┘   └──────────────┘   └──────────────┘
      │                │                │
      ▼                ▼                ▼
  ┌────────┐   ┌──────────────┐   ┌──────────────┐
  │ Editor │   │  Terminal    │   │  Help / AI   │
  │ Intents│   │  Intents     │   │  Intents     │
  │ (5)    │   │  (4)          │   │  (5)          │
  └────────┘   └──────────────┘   └──────────────┘
                       │
                       ▼
  ┌─────────────────────────────────────────────────┐
  │  .appex IntentHandler  →  AppState / WindowState│
  │  (bridges all intents to the main app)          │
  └─────────────────────────────────────────────────┘
```

## Source Files

### Implemented

| File | Responsibility |
|---|---|
| `NewDocumentIntent.swift` | `NewDocumentIntent` struct + `DocumentType` enum — creates a new untitled document of a chosen type |
| `OpenFileIntent.swift` | `OpenFileIntent` struct — opens a specific file URL in the editor |
| `SwitchPanelIntent.swift` | `SwitchPanelIntent` struct + `PanelType` enum — switches focus to a named panel |

### Planned

| File | Responsibility |
|---|---|
| `PanelToggleIntents.swift` | Toggle File Tree, Terminal, Scratchpad, Status Bar; Restore Default Layout |
| `WindowIntents.swift` | New Window, Close Tab, Close Window, Move Tab to New Window, Merge All Windows |
| `EditorIntents.swift` | Set Editor Mode, Toggle Spelling, Toggle Grammar, Find Text |
| `TerminalIntents.swift` | Send Text to Terminal, Run Command, Focus Terminal, Send Keystroke |
| `AppearanceIntents.swift` | Set Appearance (Light / Dark / System) |
| `FileIntents.swift` | Save Current Document, Open Recent File, Select File in Tree |
| `HelpIntents.swift` | Open Help Guide (Sputnik / Markdown / HTML / ASCII / Grammar), Look Up Selection |
| `AIIntents.swift` | Query Supporting AI, Show Main AI Status |

## Full Intent Inventory

### Document Intents (3)
| Intent | Parameter(s) | Description |
|---|---|---|
| `NewDocumentIntent` | `DocumentType?` | Creates a new untitled document of the chosen type |
| `OpenFileIntent` | `URL` | Opens a specific file in the editor |
| `SaveDocumentIntent` | — | Saves the currently active document |

### Panel Toggle Intents (5)
| Intent | Parameter(s) | Description |
|---|---|---|
| `ToggleFileTreeIntent` | `Bool` | Shows or hides the File Tree |
| `ToggleTerminalIntent` | `Bool` | Shows or hides the Terminal strip |
| `ToggleScratchpadIntent` | `Bool` | Shows or hides the Scratchpad |
| `ToggleStatusBarIntent` | `Bool` | Shows or hides the Status Bar |
| `RestoreLayoutIntent` | — | Restores the default three-column layout |

### Window & Tab Intents (5)
| Intent | Parameter(s) | Description |
|---|---|---|
| `NewWindowIntent` | — | Opens a new Sputnik window |
| `CloseTabIntent` | — | Closes the active tab |
| `CloseWindowIntent` | — | Closes the frontmost window |
| `MoveTabToNewWindowIntent` | — | Detaches the active tab into its own window |
| `MergeWindowsIntent` | — | Merges all open windows into one |

### Editor Intents (4)
| Intent | Parameter(s) | Description |
|---|---|---|
| `SetEditorModeIntent` | `EditorMode` | Switches the editor to Plain Text, Markdown, HTML, or ASCII Art |
| `ToggleSpellingIntent` | `Bool` | Enables or disables real-time spell checking |
| `ToggleGrammarIntent` | `Bool` | Enables or disables real-time grammar checking |
| `FindTextIntent` | `String` | Opens Find & Replace with the given search term |

### Terminal Intents (4)
| Intent | Parameter(s) | Description |
|---|---|---|
| `SendToTerminalIntent` | `String` | Pastes text into the active Terminal session |
| `RunCommandIntent` | `String` | Runs a shell command in the active Terminal session |
| `FocusTerminalIntent` | — | Moves keyboard focus to the Terminal |
| `SendKeystrokeIntent` | `String` | Sends a raw keystroke sequence to the Terminal |

### Appearance Intents (1)
| Intent | Parameter(s) | Description |
|---|---|---|
| `SetAppearanceIntent` | `AppTheme` | Sets the app to Light, Dark, or System mode |

### File Navigation Intents (3)
| Intent | Parameter(s) | Description |
|---|---|---|
| `OpenRecentFileIntent` | `String` | Opens a recently-opened file by name |
| `SelectFileInTreeIntent` | `String` | Selects a file in the File Tree by name or path |
| `RevealInFinderIntent` | — | Reveals the active file in Finder |

### Help Intents (5)
| Intent | Parameter(s) | Description |
|---|---|---|
| `OpenSputnikHelpIntent` | — | Opens the Sputnik help guide |
| `OpenMarkdownHelpIntent` | — | Opens the Markdown reference guide |
| `OpenHTMLHelpIntent` | — | Opens the HTML reference guide |
| `OpenASCIIHelpIntent` | — | Opens the ASCII Art reference guide |
| `OpenGrammarHelpIntent` | — | Opens the English Grammar reference guide |
| `LookUpSelectionIntent` | `String` | Resolves selected text against the relevant help guide |
| `MoreContextIntent` | `String, HelpTopic` | Shows "More Context" for a term in a specific help topic |

### AI Intents (2)
| Intent | Parameter(s) | Description |
|---|---|---|
| `QuerySupportingAIIntent` | `String` | Sends a query to the Supporting AI and returns the response |
| `ShowMainAIStatusIntent` | — | Displays the current Main AI model name and usage stats |

## Technical Summary

- **Key types:**
  - `NewDocumentIntent`, `OpenFileIntent`, `SwitchPanelIntent` — three currently-implemented stubs
  - `DocumentType` — `AppEnum`: `plainText`, `markdown`, `html`
  - `PanelType` — `AppEnum`: `editor`, `fileTree`, `markdownPreview`, `htmlPreview`, `pdfViewer`, `terminal`
  - `AppTheme` — `AppEnum`: `light`, `dark`, `system` (consumed by `SetAppearanceIntent`)
  - `EditorMode` — `AppEnum`: `plainText`, `markdown`, `html`, `asciiArt` (consumed by `SetEditorModeIntent`)
  - `HelpTopic` — `AppEnum`: `sputnik`, `markdown`, `html`, `asciiArt`, `grammar` (consumed by help intents)
- **Framework:** `AppIntents` (Swift only, macOS Ventura+), `AppKit` (for `@MainActor` context)
- **Threading model:** All `perform()` methods are `@MainActor`-isolated. Routing is delegated to the `.appex` `IntentHandler` extension, which bridges to `AppState`/`WindowState` via shared container or XPC
- **Execution mode:** All intents declare `openAppWhenRun = true` — Sputnik is a desktop app and intents always bring it to the foreground
- **Data flow:** `IntentHandler` in the app extension bridges intent parameters to `AppState`/`WindowState`. The intents define their parameter schema, metadata, and parameter summaries; the extension handles routing. No intent directly mutates app state
- **Dependencies:** Foundation (module owner), `AppIntents` framework; no internal Sputnik dependencies beyond Foundation
- **Failure modes:** `OpenFileIntent` throws `.needsValueError` when no file URL is provided; all other intents are stubs that return `.result()`. The `IntentHandler` bridge is the single point of failure for all routing

## Invariants

- Every intent struct declares `openAppWhenRun = true` — Sputnik is a desktop app and intents always bring it to the foreground
- All `perform()` methods are `@MainActor` — routing code shares the main actor with `AppState`
- Parameter enums conform to `AppEnum` — they get automatic type display and case display representations for Siri/Shortcuts UI
- This module never directly mutates `AppState` — routing is via the `.appex` `IntentHandler` bridge
- The full inventory covers **31 intents** across 7 categories — every panel toggle, editor operation, Terminal command, window action, appearance setting, file operation, help lookup, and AI interaction in Sputnik is exposed to Apple automation
