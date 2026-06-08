---
module: 3.1 Text
status: draft
last_updated: 2026-06-07
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
- **Key types:**
  - `EditorMode` — enum: `.plainText` · `.markdown` · `.html` · `.asciiArt`; owned by `EditorViewModel`; selected via the mode picker in the editor toolbar; controls which sub-module (3.2–3.4) is active and whether `SyntaxHighlighter` applies language colours <!-- assumed -->
  - `EditorView` — SwiftUI `NSViewRepresentable` wrapping `NSTextView` <!-- assumed -->
  - `EditorViewModel` — `@MainActor @Observable` class owning file URL, dirty state, undo stack, and current `EditorMode` <!-- assumed -->
  - `FileWatcher` — `NSFilePresenter` implementation watching the open file for external changes <!-- assumed -->
  - `CrashRecoveryStore` — serialises editor text to a temp cache file on a background `Task` <!-- assumed -->
  - `EncodingGuard` — validates file size and encoding before loading into `NSTextStorage` <!-- assumed -->
  - `SearchController` — manages the Find/Replace bar: visible/hidden state (toggled by ⌘F), search term, replacement term, current match index, and match highlight ranges in `NSTextStorage`; bar slides in at the top of the text area, above the line-number gutter <!-- assumed -->
- **Threading model:** File I/O on `Task(priority: .userInitiated)`; syntax highlighting on `Task(priority: .utility)`; crash serialisation on `Task(priority: .background)`; all `NSTextStorage` mutations and UI updates on `@MainActor`
- **Data flow:** File URL → `EncodingGuard` (size/encoding check) → `NSTextStorage` load → `EditorMode` determines syntax highlight pass (skipped for `.plainText`) → `EditorViewModel` tracks dirty state → `CrashRecoveryStore` serialises on each change; raw `NSTextStorage` text is always forwarded to the Markdown Preview panel (module 4) regardless of mode
- **State owned:** open file URL, `NSTextStorage` contents, undo/redo stack, dirty flag, crash-recovery cache path, search match list, current `EditorMode`
- **Dependencies:** Module 2 Foundation — inter-panel file routing, active workspace directory, settings (font, theme, auto-save interval); Foundation 2.7 Utilities — `DebounceTimer`
- **Failure modes:** encoding detection fails → refuse to open, surface error via Foundation error type; auto-save write fails → log and retry on next text change; external change detected by `FileWatcher` → prompt user to reload or keep local version; file exceeds size limit → refuse to open, display warning

## Shared Utilities (used by sub-modules 3.2 – 3.5)
These types live in 3.1 because they are tightly coupled to `NSTextView`/`NSTextStorage` and have no use outside the editor. Sub-modules 3.2–3.5 depend on 3.1 and access them directly — they must not be copied or re-implemented.

- **`GhostTextOverlay`** — renders an inline suggestion as a greyed secondary attribute appended after the cursor in `NSTextStorage`; exposes `show(_ suggestion: String)` and `clear()`; accepts on Tab, clears on any other keypress <!-- assumed -->
- **`SyntaxHighlighter`** — applies `NSTextStorage` colour attributes for the active language (plain text, Markdown, HTML, ASCII); runs on `Task(priority: .utility)`, writes attributes back on `@MainActor` <!-- assumed -->

General-purpose utilities that are not `NSTextView`-specific (e.g. `DebounceTimer`) live in **Foundation 2.7 Utilities**, not here.

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
