---
module: 3.1 Text
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
---

## Purpose
Provides the base text-editing surface for all file types in Sputnik — line numbers, syntax highlighting, undo/redo history, external file-watching, search/replace, save-as, auto-save with crash recovery, file-size/encoding protection, and a plaintext mode that disables language-specific assistance while keeping the Markdown preview panel available.

## Diagram
```
┌──────────────────────────────────────────────────────────────┐
│  Text Editor Window          [Mode: Plain Text ▾]            │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Find: [_______________] [< Prev] [Next >]  [✕]           │ │
│ │ Replace: [___________] [Replace] [Replace All]           │ │
│ └──────────────────────────────────────────────────────────┘ │
│  ← search bar slides in below tab bar on ⌘F; hidden at rest  │
│ ┌────┬────────────────────────────────────────────────────┐  │
│ │    │                                                    │  │
│ │ 1  │  Hello, world.                                     │  │
│ │ 2  │  This is plain text.                               │  │
│ │ 3  │  No syntax hints here.                             │  │
│ │ 4  │                                                    │  │
│ │    │                                                    │  │
│ └────┴────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
        │                        │
        ▼                        ▼
  FileWatcher               CrashRecovery
  (NSFilePresenter)         (background Task)

Mode picker drives EditorMode; Markdown Preview panel (4)
always receives the raw text regardless of mode:

  EditorMode.plainText  →  no ghost text, no syntax highlight
                           Markdown preview still renders
                           (output will be unstyled prose)

  EditorMode.markdown   →  3.2 suggestions active
                           Markdown preview renders with styles

  EditorMode.html       →  3.4 suggestions active (doctype gate
                           still applies inside 3.4)

  EditorMode.asciiArt   →  3.3 block completion active
```

## Technical Summary
- **Framework(s):** AppKit (`NSTextView` via `NSViewRepresentable`), SwiftUI, Foundation
## Source Files
| File | Responsibility |
|---|---|
| `TextEditorPanel.swift` | SwiftUI container — mode picker toolbar, search bar, editor view composition |
| `EditorView.swift` | `NSViewRepresentable` bridging `EditorTextView` — wires ghost overlay, search, spelling checker, line-number ruler, undo manager |
| `EditorTextView.swift` | `NSTextView` subclass — key handling (Tab for ghost text, ⌘F for find), single-click for quickfix popover, drag delegate for file drops, right-click summarization via extractive TF scoring; holds weak refs to ghost overlay, search, spelling checker, editor VM, help resolver |
| `EditorViewModel.swift` | `@MainActor @Observable` — file URL, dirty state, undo manager, `EditorMode`, gating flags (`htmlModeActive`, `spellCheckActive`), loaded text, load token, search controller, text view reference, file watcher, mode inference, `NSUserActivity` registration for Spotlight/Siri context |
| `EditorMode.swift` | `Sendable` enum — `.plainText`, `.markdown`, `.html`, `.asciiArt` |
| `EditorCommandHandling.swift` | Re-exports `EditorCommandHandling` protocol from `FoundationModule` |
| `EncodingGuard.swift` | Validates file size (≤10 MB) and encoding (probes first 8 KB; rejects >15% null bytes as binary); throws `Failure` on invalid |
| `FileWatcher.swift` | `NSFilePresenter` (`@unchecked Sendable`) — watches open file for external changes; prompts user to reload or keep local version |
| `CrashRecoveryStore.swift` | `@MainActor` — serialises editor text to recovery cache via `PersistenceService` on background `Task`; clears on clean save |
| `SearchController.swift` | `@MainActor @Observable` — search/replace state, match range list, current match index, highlight management in `NSTextStorage` |
| `SearchBarView.swift` | SwiftUI find/replace bar — slides in on ⌘F; debounced search, prev/next navigation, replace/replace-all |
| `LineNumberRulerView.swift` | `NSRulerView` — draws line-number gutter aligned with `NSLayoutManager` line fragments (SW-3) |
| `SyntaxHighlighter.swift` | Applies language colour attributes to `NSTextStorage` on `Task(priority: .utility)`; uses range-based re-highlight (ISS-057); no-op for `.plainText` |
| `GhostTextOverlay.swift` | `@MainActor` — renders inline suggestion as greyed text appended after cursor; shared by sub-modules 3.2/3.3/3.4 |
| `Package.swift` | SPM manifest — declares dependencies on `FoundationModule`, `ResourcesModule`, `SputnikShared` |
| `Tests/TextEditorModuleTests.swift` | Unit tests — covers `EncodingGuard`, `EditorMode`, `SearchController`, `CrashRecoveryStore`, and related types |

- **Key types:**
  - `EditorMode` — enum: `.plainText` · `.markdown` · `.html` · `.asciiArt`; owned by `EditorViewModel`; selected via the mode picker in the editor toolbar; controls which sub-module (3.2–3.4) is active and whether `SyntaxHighlighter` applies language colours
  - `EditorView` — SwiftUI `NSViewRepresentable` wrapping `EditorTextView`; wires dependencies (ghost overlay, search controller, spelling checker, line-number ruler, undo manager)
  - `EditorViewModel` — `@MainActor @Observable` class owning file URL, dirty state, undo stack, and current `EditorMode`; dependencies (`AppState`, `PersistenceService`) are injected via `init(appState:persistenceService:)` — no `NSApp.delegate` lookups (ISS-056)
  - `EditorTextView` — `NSTextView` subclass handling key events (Tab for ghost-text accept, ⌘F for find bar toggle), single-click hit-testing for quickfix popover, and drag-drop; holds weak refs to all sub-module dependencies
  - `FileWatcher` — `NSFilePresenter` implementation watching the open file for external changes
  - `CrashRecoveryStore` — `@MainActor` — serialises editor text to a temp cache file via `PersistenceService` on a background `Task`
  - `EncodingGuard` — validates file size (≥10 MB rejects) and encoding (probes first 8 KB, rejects >15% null bytes as binary); throws `Failure` on invalid
  - `SearchController` — `@MainActor @Observable` — manages the Find/Replace bar: visible/hidden state (toggled by ⌘F), search term, replacement term, current match index, and match highlight ranges in `NSTextStorage`
  - `SearchBarView` — SwiftUI find/replace bar; debounced search on term change, prev/next navigation, replace/replace-all
  - `TextEditorPanel` — SwiftUI container composing mode picker toolbar, search bar, and editor view
- **Threading model:** File I/O on `Task(priority: .userInitiated)`; syntax highlighting on `Task(priority: .utility)` using **range-based re-highlight** (expanded to nearest line boundaries + 5-line look-behind for multi-line constructs, ISS-057); crash serialisation on `Task(priority: .background)`; all `NSTextStorage` mutations and UI updates on `@MainActor`
- **Data flow:** File URL → `EncodingGuard` (size/encoding check) → `NSTextStorage` load → `EditorMode` determines syntax highlight pass (skipped for `.plainText`) → `EditorViewModel` tracks dirty state → `CrashRecoveryStore` serialises on each change; raw `NSTextStorage` text is always forwarded to the Markdown Preview panel (module 4) regardless of mode
- **State owned:** open file URL, `NSTextStorage` contents, undo/redo stack, dirty flag, crash-recovery cache path, search match list, current `EditorMode`, gating flags (`htmlModeActive`, `spellCheckActive`), `NSUserActivity` for Spotlight/Siri
- **Dependencies:** Module 2 Foundation — inter-panel file routing, active workspace directory, settings (font, theme, auto-save interval); Foundation 2.7 Utilities — `DebounceTimer`; `SputnikShared`; `ResourcesModule` (help lookups, `SputnikHelpContextResolver`)
- **F-4 (Per-panel font/background):** The text view reads `settings.resolvedTextEditorFont` and `settings.textEditorBackground` in `EditorView.configureTypography` and `updateNSView`; the resolved font falls back to the global `editorFont` when no per-panel override is set.
- **F-7 (Slash-command auto-complete):** At module init, the Text Editor registers its command sets with `SlashCommandRegistry` via `registry.register(_:)` — Markdown commands (`/h1`…`/table`…), HTML commands (`/div`…`/form`…), and ASCII art commands (`/box`…`/arrow`); each set's `category` matches the active `EditorMode`. The `NSTextView` delegate watches for `/` at a word boundary in `textView(_:shouldChangeTextIn:replacementString:)` and sets `slashPopupCommands = registry.matches(for: "")` to open `SlashCommandPopup`; subsequent keystrokes narrow the filter via `registry.matches(for: currentToken)`; `onSelect` replaces the `/…` range with `command.insert` and dismisses the popup; Escape or focus loss dismisses without insertion. `[weak self]` is used in all delegate callbacks that capture `self` (SW-2).
- **Apple Intelligence:** `EditorView.configureTypography` sets `writingToolsBehavior = .complete` on macOS 15+ (guarded by `#available`). `EditorViewModel` registers an `NSUserActivity` (`com.lukeisham.sputnik.editing`) on each file open for Spotlight indexing and Siri Suggestions. Right-click context menu includes "Summarize Locally" — extractive TF-scored sentence selection via `NLTokenizer`, fully on-device.
- **Failure modes:** encoding detection fails → refuse to open, surface error via Foundation error type; auto-save write fails → log and retry on next text change; external change detected by `FileWatcher` → prompt user to reload or keep local version; file exceeds size limit → refuse to open, display warning

## Shared Utilities (used by sub-modules 3.2 – 3.5)
These types live in 3.1 because they are tightly coupled to `NSTextView`/`NSTextStorage` and have no use outside the editor. Sub-modules 3.2–3.5 depend on 3.1 and access them directly — they must not be copied or re-implemented.

- **`GhostTextOverlay`** — `@MainActor` class; renders an inline suggestion as a greyed secondary attribute appended after the cursor in `NSTextStorage`; exposes `show(_ suggestion: String)` and `clear()`; accepts on Tab, clears on any other keypress; ghost insertions wrapped in `undoManager.disableUndoRegistration`
- **`SyntaxHighlighter`** — applies `NSTextStorage` colour attributes for the active language (plain text, Markdown, HTML, ASCII); runs on `Task(priority: .utility)`, writes attributes back on `@MainActor`; uses **range-based re-highlight** — `highlight(mode:editedRange:)` only re-colours the affected range plus a 5-line look-behind margin, extracted from the `NSTextView.textDidChange` notification's `userInfo["NSRange"]` (ISS-057)

General-purpose utilities that are not `NSTextView`-specific (e.g. `DebounceTimer`) live in **Foundation 2.7 Utilities**, not here.

## Invariants
- `EditorViewModel` is `@MainActor` — all observable state mutations happen on the main actor; text loading and syntax highlighting run on background `Task`s (SW-1)
- All sub-module dependencies (`ghostTextOverlay`, `searchController`, `spellingChecker`, `editorViewModel`, `settings`, `helpContextResolver`) are held as **weak** references in `EditorTextView` — no retain cycles (SW-2)
- The **only** file-open path to other panels is `InterPanelRouter.open(_:)` — never direct `WindowState.openDocument()` (SR-1, SC-9)
- `GhostTextOverlay` and `SyntaxHighlighter` are defined once in 3.1 — sub-modules 3.2–3.4 must never re-implement or copy them (SC-2, SC-8)
- `EncodingGuard.validate(_:)` is called **before** any file content is loaded into `NSTextStorage` — oversized or binary files never consume RAM in the text storage (SR-3)
- `FileWatcher` captures `[weak self]` in all closures and presenter callbacks (SW-2)
- `CrashRecoveryStore` schedules writes at `.background` priority — serialisation never competes with the typing path (SR-4)
- `SyntaxHighlighter` uses range-based re-highlight — `highlight(mode:editedRange:)` only re-colours the affected range plus a 5-line look-behind margin, O(range) instead of O(n) per keystroke (ISS-057, SR-4)
- `FileWatcher` is `@unchecked Sendable` — all mutable state is accessed from `@MainActor` callbacks only

## Spec Reference
> Extracted verbatim from `readme.md`:

```
3. EDITOR WINDOW = the main text editing area where users write Markdown content, opens either text or binary files or Markdown files. 
  1. Line Numbers
  2. Syntax Highlighting
  3. File State & History (eg Undo/Redo)
  4. External File-Watchers 
  5. Search and Replace (Find in File)
  6. SaveAs function 
  7. Auto-Save and Crash Recovery (frequent state serialization to a temporary cache file).
  8. File Size and Encoding Protection (refuse to open or truncate non-text/binary files to prevent RAM exhaustion).
```
