---
module: 10 ASCII Studio
status: active
last_updated: 2026-06-15
last_verified: 2026-06-15
plan: 1 Setup/Plans Completed/2026-06-15 3.3 + 10 ASCII Studio — Plan C UX features.md
---

## Purpose
Provides the **advanced (Tier 2)** ASCII art workflow: import an image and convert it to ASCII text with brightness/contrast/dithering/edge-detection controls, edit the result on an interactive character-grid canvas, browse a bundled clipart library, and save or insert the output. Triggered by ⌘⌥A or Format → ASCII Studio, which opens a dockable column panel registered in Foundation as `PanelID.asciiStudio`.

Basic (Tier 1) box-drawing auto-completion stays in module 3.3.

## Diagram

```
  ⌘⌥A / Format → ASCII Studio
         │
         ▼
  EditorViewModel.showASCIIStudio()
         │
  AppState.toggleColumn(.asciiStudio)
         │
  WindowState.toggleColumn → DynamicPanelLayout.addColumn(.asciiStudio)
         │
         ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │  ASCII  [✕]   dockable column panel (PanelID.asciiStudio)        │
  │  ─────────────────────────────────────────────────────────────   │
  │  [Image → ASCII]           [Library]                             │
  │                                                                  │
  │  IMAGE → ASCII TAB                                               │
  │  ┌──────────────────────────────────────────────────────┐        │
  │  │ [Import PNG / JPEG / TIFF]                           │        │
  │  │                                                      │        │
  │  │ Mode:   [Luminance ▾] [Line-art]                    │        │
  │  │ Width:  [────●───] 80 cols                           │        │
  │  │ Style:  [Block ▾]  Invert [ ]                        │        │
  │  │ ▶ Adjustments ────────────────────────────────────   │        │
  │  │   Brightness: [────●───]  Contrast: [────●───]      │        │
  │  │   Dither: [ ]                                        │        │
  │  │                                                      │        │
  │  │  ┌────────────────────────────────────┐              │        │
  │  │  │  @@@##SS%%??**                     │  editable    │        │
  │  │  │  ++;;::,,..                        │  canvas      │        │
  │  │  │                                    │  (⌘Z/⌘⇧Z)  │        │
  │  │  └────────────────────────────────────┘              │        │
  │  │  Edit: [Select] [Replace] [Align ▾] [Fill]          │        │
  │  │                                                      │        │
  │  │  [Open .txt…]  [Save as .txt…]  [Insert at Cursor]  │        │
  │  └──────────────────────────────────────────────────────┘        │
  │                                                                  │
  │  LIBRARY TAB                                                     │
  │  [Frames] [Arrows] [Dividers] [Decorative] [Symbols]            │
  │  ┌──────────────┐ ┌──────────────┐                              │
  │  │ ┌──────────┐ │ │  ─────────   │                              │
  │  │ └──────────┘ │ │  ═══════════  │                              │
  │  └──────────────┘ └──────────────┘                              │
  │                         [Insert at Cursor]                       │
  └──────────────────────────────────────────────────────────────────┘

  CONVERSION PIPELINE (Image → ASCII tab)
  ────────────────────────────────────────

  NSImage
     │  CGBitmapContext (target width × rows)
     │
  ┌──┴──────────────────────────────────────────────────┐
  │  Mode: Luminance                                     │
  │  Rec.601 luminance → density ramp character          │
  │  Block / Minimal / Braille / ASCII / Wide            │
  │  ± brightness, ± contrast, Floyd–Steinberg dither   │
  ├──────────────────────────────────────────────────────┤
  │  Mode: Line-art                                      │
  │  ASCIIEdgeDetector (Core Image Sobel)                │
  │  edge intensity → line glyphs (/ \ | _ -)           │
  └──┬──────────────────────────────────────────────────┘
     │ String
     ▼
  ASCIIImageEditor.load()   ←  also: ASCIIExporter.open()
     │
  editable canvas + undo stack
     │
  ┌──┴──────────────────┬──────────────────────────┐
  ▼                     ▼                          ▼
ASCIIExporter.save()  ASCIIStudioCoordinator   [Library tab]
(.txt via NSSavePanel) .insertAtCursor()       ASCIILibraryBrowser
                        into NSTextView         .insert() into NSTextView
```

## Source Files

| File | Responsibility |
|---|---|
| `ASCIIStudioView.swift` | Top-level SwiftUI two-tab panel view — Image → ASCII tab (controls, editable canvas, action bar with Copy button) and Library tab (with search field); owns all `@State` for conversion settings, editor, library search, and warn-before-discard alert; includes `OutputPreset` enum |
| `MonoGridView.swift` | `NSViewRepresentable` wrapping `GridNSView: NSView`; draws the character grid in monospaced glyphs; highlights the selected cell; `mouseDown` converts click to (row, col) and calls `ASCIIImageEditor.selectCell(row:col:)` |
| `ImageToASCIIConverter.swift` | Converts `NSImage` → ASCII `String` via `CGBitmapContext`; Rec.601 luminance ramp (6 styles incl. Custom) with brightness/contrast/light-threshold/Floyd–Steinberg & Bayer dither; composite mode (luminance + edge overlay); delegates edge-detection to `ASCIIEdgeDetector`; runs on `Task(priority: .userInitiated)` |
| `RampSwatchView.swift` | SwiftUI view rendering up to 20 ramp characters over a black-to-white gradient; updates live as `rampStyle` or `customRampString` changes |
| `ASCIIEdgeDetector.swift` | Core Image Sobel edge-detection on the luminance channel; returns a 2-D intensity grid; maps high-intensity pixels to line glyphs (`/ \ \| _ -`) per `EdgeStyle` (Simple/Shaded/Dense) |
| `ASCIIImageEditor.swift` | `@MainActor ObservableObject`; flat character-grid model; operations: `load`, `replaceCharacter`, `batchReplace`, `replaceSelection`, `align`, `fill`; `hasManualEdits` flag; scoped `UndoManager` for ⌘Z/⌘⇧Z |
| `ASCIIExporter.swift` | `@MainActor enum`; `save(content:suggestedFilename:)` via `NSSavePanel` (`.txt`, filename retains source image name); `open()` via `NSOpenPanel`; both surface `NSAlert` on read/write failure |
| `ASCIIArt.swift` | `Sendable, Identifiable, Equatable` value type; carries `asciiContent`, `sourceImageURL`, `style`, `width`, `tags`, `createdAt` |
| `ASCIILibraryBrowser.swift` | `@MainActor` class; lazy-loads bundled `.txt` clip files per category from `Resources/ASCIILibrary/<category>/`; `clips(for:)` caches per category; `insert(_:into:)` replaces at cursor |
| `ASCIIStudioCoordinator.swift` | `@MainActor enum`; `insertAtCursor(_:into:)` — replaces at `NSTextView.selectedRange()`; `activeTextView()` — finds the key-window first responder |
| `Package.swift` | SPM manifest — depends on `FoundationModule`, `ResourcesModule`; product `ASCIIStudioModule` |
| `Tests/ASCIIStudioModuleTests.swift` | Swift Testing unit tests — covers `ASCIIArt` model, `ImageToASCIIConverter` ramp/brightness/dither logic, `ASCIIImageEditor` operations and undo, `ASCIIExporter` filename-retention rule |

## Technical Summary

- **Framework(s):** SwiftUI (panel chrome, controls, tab bar), AppKit (`NSTextView` insertion, `NSSavePanel`/`NSOpenPanel`, `NSAlert`, `NSImage`), CoreGraphics (`CGBitmapContext`), Core Image (Sobel edge-detection in `ASCIIEdgeDetector`), Foundation
- **Panel registration:** `PanelID.asciiStudio` (badge `"ASCII"`) is declared in Foundation `2 Foundation/2.4 UI and UX/PanelID.swift`. The panel is toggled via `AppState.toggleColumn(.asciiStudio)` → `WindowState.toggleColumn` → `DynamicPanelLayout.addColumn`/`removeColumn`. Persistence is automatic: `PanelID: String, Codable` round-trips via raw value `"asciiStudio"` in `DynamicPanelLayout` → `LayoutState` → `layout.json`. `ContentView.panelContentView` routes `.asciiStudio` → `ASCIIStudioView()`.
- **Trigger:** `EditorViewModel.showASCIIStudio()` (module 3.1) calls `AppState.toggleColumn(.asciiStudio)` — re-points the old floating-panel trigger (ISS-041) without breaking the ⌘⌥A shortcut or the Format menu item.
- **Threading model:** All `NSTextView`, `NSTextStorage`, and panel (`NSSavePanel`/`NSOpenPanel`) operations are `@MainActor`. Image conversion (`ImageToASCIIConverter.convert`) runs on `Task(priority: .userInitiated)` — the user is watching the live preview. `ASCIIEdgeDetector` is called from the same task. `ASCIILibraryBrowser` clips are loaded on first category access, `@MainActor`.
- **Key types:**
  - `ImageToASCIIConverter` — pure `enum`; `convert(image:settings:)` where `Settings` carries `width`, `invert`, `style` (`RampStyle`: Block/Minimal/Braille/ASCII/Wide/Custom), `customRampString` (active when style == .custom; falls back to .ascii if empty), `mode` (`.luminance` / `.lineArt` / `.composite`), `brightness` (−1…1), `contrast` (0…3), `ditherMode` (`DitherMode`: none/floydSteinberg/bayer), `edgeStyle`, `lightThreshold` (0.5…1.0; pixels brighter than this → space); luminance path: `CGBitmapContext` pixel grid → Rec.601 → light-threshold check → ramp index ± brightness/contrast → optional Floyd–Steinberg or Bayer 4×4 dither; composite path (two-pass): luminance pass + edge overlay (cells with edge intensity > 0.4 use border chars from last 3 ramp entries); line-art path: delegates to `ASCIIEdgeDetector`; `effectiveCharacters` computed property on `Settings` resolves the active ramp
  - `DitherMode` — `enum` (none / floydSteinberg / bayer); replaces the old `dither: Bool` field
  - `OutputPreset` — `enum` (small=32cols / standard=72cols / large=120cols) in `ASCIIStudioView`; `saveAtPreset(_:)` re-converts from `selectedImage` without touching the live canvas
  - `RampSwatchView` — lightweight SwiftUI view; takes `[String]` character array, renders up to 20 chars over `LinearGradient` black→white
  - `ASCIIEdgeDetector` — `enum`; `detect(cgImage:width:height:edgeStyle:)` → 2-D `[[Float]]`; uses `CIFilter(name: "CISobelGradients")` on the luminance channel; maps intensity to `EdgeStyle`-specific glyph set
  - `ASCIIImageEditor` — `@MainActor ObservableObject`; row-major `[Character]` grid; each mutating operation registers its inverse on `self.undoManager` before writing; `hasManualEdits` trips on any character change and resets on `load()`; `undoManager` is replaced (cleared) on each `load()` call; `selectedCell: (row: Int, col: Int)?` holds the tap-to-edit selection; `selectCell(row:col:)` and `replaceSelectedCell(with:)` implement tap-to-edit via `MonoGridView`
  - `ASCIIExporter` — `@MainActor enum`; save path: `NSSavePanel` → `String.write(to:atomically:encoding:)`; open path: `NSOpenPanel` → `String(contentsOf:encoding:)` → returns `(content, filenameWithoutExtension)`; errors surfaced via `NSAlert`, never silently swallowed
  - `ASCIIStudioView` — all `@State`; owns `imageEditor: ASCIIImageEditor` and `showDiscardWarning: Bool`; `maybeReconvert()` checks `imageEditor.hasManualEdits` before re-running conversion and sets `showDiscardWarning = true` if dirty; `.alert("Discard Edits?", ...)` lets the user confirm or cancel
  - `ASCIILibraryBrowser` — `@MainActor` class; `Category` enum (Frames/Arrows/Dividers/Decorative/Symbols); `clips(for:)` reads `ResourcesModule.bundle` at `ASCIILibrary/<category>/` on first access, then caches; `insert(_:into:)` uses `NSTextStorage.replaceCharacters(in: textView.selectedRange(), with:)`
- **Library source of truth:** `ASCIILibraryBrowser` reads the filesystem directly from `ResourcesModule.bundle` and is the single source the Studio's Library tab consumes. The `ASCIILibrary` actor in module 9.1 uses `index.json`-based search for the help system — the two are independent; the Studio does not use the actor.
- **Warn-before-discard:** any action that would overwrite the canvas (re-convert, new import, open `.txt`) calls `maybeReconvert()` / checks `imageEditor.hasManualEdits`; if `true`, presents a SwiftUI `.alert` requiring explicit confirmation before discarding. Re-conversion after confirmation calls `imageEditor.load()` which resets `hasManualEdits` and clears the undo stack.
- **State owned:** conversion settings (width, invert, style, customRampString, mode, brightness, contrast, ditherMode, edgeStyle, lightThreshold), selected image (`NSImage?`), live ASCII preview string, `ASCIIImageEditor` (character grid + undo stack + `hasManualEdits`), selected library category. No document state — the module never writes `AppState.openDocuments` (SR-1).
- **Dependencies:** Foundation 2.2 (`AppState.toggleColumn` trigger path); Foundation 2.4 (`PanelID.asciiStudio`, `SputnikColor`, panel chrome); Foundation 2.1 (`EditorCommandHandling.showASCIIStudio()` calls `AppState.toggleColumn`); Module 9 `ResourcesModule` (bundled `ASCIILibrary` clips); Module 3.1 (`NSTextView` insert target via `ASCIIStudioCoordinator`). No dependency on modules 4, 5, 7, or 8.
- **Failure modes:**
  - Image import fails or format unsupported → `NSOpenPanel` selection cancelled silently; `CGBitmapContext` pixel read on zero-alpha → treated as white (luminance 1.0)
  - Edge-detection `CIFilter` unavailable (future OS removal) → `ASCIIEdgeDetector` falls back to all-spaces output; no crash
  - `NSSavePanel`/`NSOpenPanel` cancelled → returns `false`/`nil`; no side-effects
  - Save/open read-write error → `NSAlert` shown; canvas untouched
  - Library `.txt` file missing from bundle → `clips(for:)` returns empty array, silently; category shows an empty list
  - Very large image → `CGBitmapContext` is created at the target `width × rows` size (not full pixel resolution); large output strings may be slow to render in the canvas — no hard cap, but `Task(priority: .userInitiated)` keeps the UI responsive

## Invariants
- `ImageToASCIIConverter.convert` runs on a **non-`@MainActor` background Task** — never called synchronously on the main thread (SR-4)
- `ASCIIEdgeDetector` and `ASCIIImageEditor` are built on **Apple imaging/foundation APIs only** — no third-party packages (SR-5)
- `ASCIIImageEditor.undoManager` is **reset on every `load()`** call — the undo stack never carries history across separate conversions or file opens
- `hasManualEdits` trips on **any character mutation** and must be checked before any re-convert/import/open that would overwrite the canvas
- `ASCIILibraryBrowser` is the **only** path for bundled library clips in the Studio — never read `ASCIILibrary` actor (9.1) from this module (SR-1)
- This module **never writes `AppState.openDocuments`** — insert-at-cursor is the only editor interaction, routed through `ASCIIStudioCoordinator` (SR-1)
- All `NSSavePanel`/`NSOpenPanel`/`NSAlert` calls are `@MainActor` — never invoked from a background task (SW-1)
