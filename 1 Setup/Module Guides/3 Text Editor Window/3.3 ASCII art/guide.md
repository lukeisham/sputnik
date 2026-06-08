---
module: 3.3 ASCII art
status: draft
last_updated: 2026-06-08
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

## Technical Summary
- **Framework(s):** AppKit (`NSTextView`, `NSTextStorage`, `NSPanel`), CoreGraphics (`CGBitmapContext`, `CGImage`), Foundation
- **Key types:**
  - `ASCIIArtLanguageProvider` — recognises box-drawing sequences (`┌─┐│└┘`, `+--`, `|`) and partial patterns; returns either a ghost-text character or a block-completion payload <!-- assumed -->
  - `BlockCompletion` — replaces a partial box-drawing pattern with a complete ASCII frame on Tab <!-- assumed -->
  - `GhostTextOverlay` — shared with 3.2/3.4; lives in 3.1 Text <!-- assumed -->
  - `ASCIIStudioPanel` — floating `NSPanel` opened by ⌘⌥A or Format → ASCII Studio; hosts the two tabs below <!-- assumed -->
  - `ImageToASCIIConverter` — accepts an `NSImage`; draws it into a `CGBitmapContext` at the target column width; reads each pixel's RGB values; computes luminance with Rec.601 weighting (`0.299R + 0.587G + 0.114B`); maps the 0–1 luminance value to a character from the selected density ramp; returns a plain `String`; supports invert and three ramp styles (Block `@#S%?*+;:,. `, Minimal `#. `, Braille `⣿⣷⣦⣄⡀ `) <!-- assumed -->
  - `ASCIILibraryBrowser` — loads bundled `.txt` clip files from `Resources/ASCIILibrary/<category>/` lazily at first access; displays a grid preview per item; inserts selected item at cursor via `NSTextStorage` replacement <!-- assumed -->
- **Threading model:** Tier 1 pattern matching on `Task(priority: .utility)`; `ImageToASCIIConverter` rendering on `Task(priority: .userInitiated)` (user is waiting for preview); all `NSTextStorage` writes and UI updates on `@MainActor`
- **Data flow:**
  - *Tier 1:* keypress → `DebounceTimer` → `ASCIIArtLanguageProvider.suggest(at:)` → `GhostTextOverlay` or `BlockCompletion` → user accepts (Tab) or dismisses
  - *Tier 2 image:* import image → `ImageToASCIIConverter.convert(_:width:invert:style:)` → live preview string → user clicks Insert → `NSTextStorage` replacement at cursor
  - *Tier 2 library:* open panel → browse category → select clip → Insert → `NSTextStorage` replacement at cursor
- **State owned:** current ghost-text suggestion; pending block-completion payload; `ASCIIStudioPanel` open/closed state; current converter settings (width, invert, style); selected library category
- **Dependencies:** 3.1 Text — `NSTextView` delegate chain, `GhostTextOverlay`; Foundation 2.7 Utilities — `DebounceTimer`; Module 2 Foundation — settings (suggestions enabled, trigger key binding)
- **Failure modes:** pattern match returns nil → clear ghost text silently; block expansion at wrong cursor position → no-op; image import fails or format unsupported → show inline error in Studio panel, do not crash; `CGBitmapContext` pixel read returns zero-alpha → treat as white (luminance 1.0); library `.txt` file missing from bundle → skip item silently, log warning; converter produces output wider than editor column width → insert as-is, user can adjust width control

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
