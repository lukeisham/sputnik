---
module: 3.3 ASCII art
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
---

## Purpose
Provides two tiers of ASCII art support in the text editor: a lightweight auto tier for keyboard-driven box-drawing diagrams, and a manually opened Studio panel for image-to-ASCII conversion (using luminance mapping) and a bundled clipart library.

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
  TIER 2 — STUDIO  (⌘⌥A or menu → Format → ASCII Studio)
─────────────────────────────────────────────────────────────

  ASCIIStudioPanel (floating panel)
  ┌────────────────────────────────────────────────────────┐
  │  [Image → ASCII]        [Library]                      │
  ├────────────────────────────────────────────────────────┤
  │  IMAGE → ASCII tab                                     │
  │                                                        │
  │  [Import PNG / JPEG / TIFF]                            │
  │                                                        │
  │  NSImage → CGBitmapContext → pixel grid                │
  │                                                        │
  │  Per pixel:                                            │
  │    luminance = 0.299R + 0.587G + 0.114B               │
  │    (Rec.601 perceptual weighting)                      │
  │                                                        │
  │  Map luminance → density ramp character:               │
  │    dark  @#S%?*+;:,.        light                      │
  │    (ramp can be inverted for dark backgrounds)         │
  │                                                        │
  │  Controls:                                             │
  │    Width: [────●──────] 80 cols                        │
  │    Invert: [ ] (for dark background)                   │
  │    Style:  [Block ▾] (Block / Minimal / Braille)       │
  │                                                        │
  │  ┌──────────────────┐                                  │
  │  │  @@@##SS%%??**   │  ← live preview                  │
  │  │  ++;;::,,..      │                                  │
  │  └──────────────────┘                                  │
  │                          [Insert at cursor]            │
  ├────────────────────────────────────────────────────────┤
  │  LIBRARY tab                                           │
  │                                                        │
  │  [Frames] [Arrows] [Dividers] [Decorative] [Symbols]  │
  │                                                        │
  │  ┌──────────────┐  ┌──────────────┐                   │
  │  │ ┌──────────┐ │  │  ─────────   │                   │
  │  │ │          │ │  │  ─ ─ ─ ─ ─   │                   │
  │  │ └──────────┘ │  │  ═══════════  │                   │
  │  └──────────────┘  └──────────────┘                   │
  │                          [Insert at cursor]            │
  └────────────────────────────────────────────────────────┘
```

## Source Files
| File | Responsibility |
|---|---|
| `ASCIIArtLanguageProvider.swift` | `@MainActor` — detects box-drawing sequences at the cursor; dispatches ghost-text or `BlockCompletion` payloads |
| `BlockCompletion.swift` | `@MainActor` — stages a partial-to-full ASCII frame payload; `apply(to:)` replaces pattern with completed frame on Tab |
| `ASCIIStudioPanel.swift` | `NSPanel` — floating non-activating tool window for the ASCII Studio (⌘⌥A) |
| `ASCIIStudioView.swift` | SwiftUI two-tab content: Image → ASCII (live preview with width/invert/style controls) and Library (browse clips by category) |
| `ImageToASCIIConverter.swift` | Converts `NSImage` to ASCII string via `CGBitmapContext` pixel reads + Rec.601 luminance mapping; supports Block, Minimal, Braille ramp styles |
| `ASCIILibraryBrowser.swift` | `@MainActor` — lazy-loads bundled `.txt` clip files per category from `Resources/ASCIILibrary/<category>/`; `clips(for:)` caches per category |

## Technical Summary
- **Framework(s):** AppKit (`NSTextView`, `NSTextStorage`, `NSPanel`), CoreGraphics (`CGBitmapContext`, `CGImage`), Foundation
- **Key types:**
  - `ASCIIArtLanguageProvider` — `@MainActor` class; recognises box-drawing sequences (`┌─┐│└┘`, `+--`, `|`) and partial patterns; returns either a ghost-text character or a block-completion payload
  - `BlockCompletion` — `@MainActor` class; replaces a partial box-drawing pattern with a complete ASCII frame on Tab; staged via `Payload` (pattern + frame + preview)
  - `GhostTextOverlay` — shared with 3.2/3.4; lives in 3.1 Text
  - `ASCIIStudioPanel` — `NSPanel` singleton; floating non-activating tool window opened by ⌘⌥A or Format → ASCII Studio; hosts the two tabs via `ASCIIStudioView`
  - `ASCIIStudioView` — SwiftUI two-tab content view: Image → ASCII tab with live preview, width/invert/style controls; Library tab with category browsing and clip insertion
  - `ImageToASCIIConverter` — `enum`; accepts an `NSImage`; draws it into a `CGBitmapContext` at the target column width; reads each pixel's RGB values; computes luminance with Rec.601 weighting (`0.299R + 0.587G + 0.114B`); maps the 0–1 luminance value to a character from the selected density ramp; returns a plain `String`; supports invert and three ramp styles (Block `@#S%?*+;:,. `, Minimal `#. `, Braille `⣿⣷⣦⣄⡀ `)
  - `ASCIILibraryBrowser` — `@MainActor` class; loads bundled `.txt` clip files from `Resources/ASCIILibrary/<category>/` lazily at first access per category; `clips(for:)` returns cached `[Clip]`; provides `insert(_:into:)` for `NSTextStorage` replacement at cursor
- **Threading model:** Tier 1 pattern matching on `Task(priority: .utility)`; `ImageToASCIIConverter` rendering on `Task(priority: .userInitiated)` (user is waiting for preview); all `NSTextStorage` writes and UI updates on `@MainActor`
- **Data flow:**
  - *Tier 1:* keypress → `DebounceTimer` → `ASCIIArtLanguageProvider.suggest(at:)` → `GhostTextOverlay` or `BlockCompletion` → user accepts (Tab) or dismisses
  - *Tier 2 image:* import image → `ImageToASCIIConverter.convert(_:width:invert:style:)` → live preview string → user clicks Insert → `NSTextStorage` replacement at cursor
  - *Tier 2 library:* open panel → browse category → select clip → Insert → `NSTextStorage` replacement at cursor
- **State owned:** current ghost-text suggestion; pending block-completion payload; `ASCIIStudioPanel` open/closed state; current converter settings (width, invert, style); selected library category
- **Dependencies:** 3.1 Text — `NSTextView` delegate chain, `GhostTextOverlay`; Foundation 2.7 Utilities — `DebounceTimer`; Module 2 Foundation — settings (suggestions enabled, trigger key binding)
- **Failure modes:** pattern match returns nil → clear ghost text silently; block expansion at wrong cursor position → no-op; image import fails or format unsupported → show inline error in Studio panel, do not crash; `CGBitmapContext` pixel read returns zero-alpha → treat as white (luminance 1.0); library `.txt` file missing from bundle → skip item silently, log warning; converter produces output wider than editor column width → insert as-is, user can adjust width control

## Invariants
- `ASCIIArtLanguageProvider` is `@MainActor` — all `NSTextView`/`NSTextStorage` access happens on the main actor (SW-1)
- Ghost-text rendering uses the shared `GhostTextOverlay` from 3.1 — never re-implemented or copied (SC-2, SC-8)
- `ImageToASCIIConverter` runs on `Task(priority: .userInitiated)` — user is waiting for live preview in Studio panel (SR-4)
- `ASCIILibraryBrowser` loads clips per-category on first access — never all upfront (SR-3)
- `ASCIIStudioPanel` is a singleton — only one Studio instance exists at any time

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
