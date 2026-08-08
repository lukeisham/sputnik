---
module: 3.3 ASCII art
status: active
last_updated: 2026-06-15
last_verified: 2026-06-15
plan: 1 Setup/Plans Completed/2026-06-15 3.3 + 10 ASCII Studio — Plan C UX features.md
---

## Purpose
Provides the **basic (Tier 1)** ASCII art layer in the text editor: keyboard-driven box-drawing auto-completion and ghost-text hints. The **advanced (Tier 2)** ASCII Studio — image conversion, library browser, editor tools, file export — has been extracted into its own **module 10 ASCII Studio** (plan: `2026-06-12 10 ASCII Studio Deepen ASCII Studio.md`).

## Diagram
```
─────────────────────────────────────────────────────────────
  TIER 1 — AUTO  (typing-triggered, no manual action needed)
─────────────────────────────────────────────────────────────

  Keypress in NSTextView (3.1)
           │
           ▼
    DebounceTimer (Foundation 2.7)
           │  typing paused
           ▼
  ASCIIArtLanguageProvider
  ┌──────────────────────────┐
  │  detect box-drawing      │
  │  sequence or partial     │
  │  frame at cursor         │
  │  e.g. +-- or ┌─          │
  └──────────────────────────┘
           │
     ┌─────┴──────────┐
     ▼                ▼
GhostTextOverlay  BlockCompletion
(next char hint)  (expand to full
                   frame on Tab)

─────────────────────────────────────────────────────────────
  ADVANCED (TIER 2) — ASCII STUDIO  (⌘⌥A or Format → ASCII Studio)
─────────────────────────────────────────────────────────────

  Moved to module 10 ASCII Studio.
  ⌘⌥A / Format → ASCII Studio now opens the dockable column panel
  via AppState.toggleColumn(.asciiStudio) → WindowState.toggleColumn.
  See module 10 guide for the full diagram.
```

## Source Files
| File | Responsibility |
|---|---|
| `ASCIIArtLanguageProvider.swift` | `@MainActor` — detects box-drawing sequences at the cursor; dispatches ghost-text or `BlockCompletion` payloads |
| `BlockCompletion.swift` | `@MainActor` — stages a partial-to-full ASCII frame payload; `apply(to:)` replaces pattern with completed frame on Tab |

*The following files were **moved to `10 ASCII Studio/Sources/`** as part of the Deepen ASCII Studio plan (2026-06-12):*
`ASCIIStudioView.swift`, `ImageToASCIIConverter.swift`, `ASCIILibraryBrowser.swift`, `ASCIIArt.swift`, `ASCIIImageEditor.swift`, `ASCIIEdgeDetector.swift`, `ASCIIExporter.swift`, `ASCIIStudioCoordinator.swift`

## Technical Summary
- **Framework(s):** AppKit (`NSTextView`, `NSTextStorage`), Foundation
- **Key types:**
  - `ASCIIArtLanguageProvider` — `@MainActor` class; recognises box-drawing sequences and partial patterns; returns either a ghost-text character or a block-completion payload. Box-frame triggers: `+--` / `┌─` (ASCII / single-line), `╔═` (double-line), `╭─` (rounded-corner)
  - `BlockCompletion` — `@MainActor` class; replaces a partial box-drawing pattern with a complete ASCII frame on Tab; staged via `Payload` (pattern + frame + preview)
  - `GhostTextOverlay` — shared with 3.2/3.4; lives in 3.1 Text
- **Threading model:** Basic (Tier 1) pattern matching on `Task(priority: .utility)`; all `NSTextStorage` writes and UI updates on `@MainActor`
- **Data flow:**
  - *Basic (Tier 1):* keypress → `DebounceTimer` → `ASCIIArtLanguageProvider.suggest(at:)` → `GhostTextOverlay` or `BlockCompletion` → user accepts (Tab) or dismisses
  - *Advanced (Tier 2):* ⌘⌥A / Format → ASCII Studio → `EditorViewModel.showASCIIStudio()` → `AppState.toggleColumn(.asciiStudio)` → dockable column panel in module 10
- **State owned:** current ghost-text suggestion; pending block-completion payload
- **Dependencies:** 3.1 Text — `NSTextView` delegate chain, `GhostTextOverlay`; Foundation 2.7 Utilities — `DebounceTimer`; Foundation 2.2 — `AppState.toggleColumn` (Studio trigger)
- **Failure modes:** pattern match returns nil → clear ghost text silently; block expansion at wrong cursor position → no-op

## Invariants
- `ASCIIArtLanguageProvider` is `@MainActor` — all `NSTextView`/`NSTextStorage` access happens on the main actor (SW-1)
- Ghost-text rendering uses the shared `GhostTextOverlay` from 3.1 — never re-implemented or copied
- This module owns **only basic (Tier 1)** box-drawing; all advanced Studio features live in module 10 — never re-add Studio files here (SR-1)

## Bundled library structure
```
Resources/
└── ASCIILibrary/
    ├── Frames/        ← box styles: single, double, rounded, heavy
    ├── Arrows/        ← directional, double, curved
    ├── Dividers/      ← solid, dashed, double, wave
    ├── Decorative/    ← borders, corners, ornaments
    └── Symbols/       ← stars, bullets, checkmarks, crosses
```
Each file is a plain `.txt` clip. The library is static — shipped in the app bundle, not user-editable. <!-- assumed -->

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  10. ASCII art support (Inline Suggestions / Ghost Text, Debouncing, Block Completion)
```
