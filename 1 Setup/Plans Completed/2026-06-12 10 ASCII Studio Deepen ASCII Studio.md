---
plan: Deepen ASCII Studio
module: 10 ASCII Studio (new) + 3 Text Editor Window (3.3 ASCII art) + 2 Foundation (panel layout) + 9 Resources (9.1 Library)
created: 2026-06-12
status: complete
related_issues: ISS-041 (resolved — Studio trigger), ISS-045 (resolved — resource bundling)
---

> ⚠️ **Foundation touch (per !GenerateAPlan rule):** promoting the Studio from a floating
> `NSPanel` to a dockable layout panel requires a new `.asciiStudio` case in `PanelID`
> plus layout/routing/persistence wiring in module 2. Foundation changes ripple to every
> module — review step 2 with extra care.

> 🔎 **Current state (validated against source 2026-06-12) — this is migrate-and-extend, NOT greenfield.**
> A working ASCII Studio already exists in `3 Text Editor/3.3 ASCII art/`:
> - `ASCIIStudioPanel.swift` / `ASCIIStudioView.swift` — a floating `NSPanel` (⌘⌥A, Format → ASCII Studio; wired per resolved ISS-041) with two tabs: **Image → ASCII** (live preview) and **Library**.
> - `ImageToASCIIConverter.swift` — already supports **width, invert, and Block/Minimal/Braille ramp styles** via Rec.601 luminance mapping. Does **not** yet support brightness, contrast, or dithering.
> - `ASCIILibraryBrowser.swift` — reads bundled `.txt` clips from `Resources/ASCIILibrary/<category>/`.
> - Output is **"Insert at Cursor" only** — there is no save-to-`.txt`-file path, and no ASCII editing tools.
>
> **Therefore the real deltas are:** (a) a dockable panel + new module home, (b) brightness/contrast/dithering, (c) an ASCII editor with tools, (d) file export, (e) resolving the duplicate library systems. Features already present (import, conversion, live preview, style presets, insert-at-cursor, library browse) are **migrated, not rebuilt**.

## Purpose
Promote Sputnik's existing floating ASCII Studio into a dedicated, dockable `10 ASCII Studio` module and extend it with the capabilities it lacks today — brightness/contrast/dithering, an ASCII editor with basic tools, and saving to a `.txt` file — while keeping Tier-1 box-drawing assistance in `3 Text Editor`.

## Success Condition
From a running build, the user can: open the ASCII Studio as a **dockable panel** → import an image → adjust width, invert, style, **and new brightness/contrast/dithering** controls with the existing **live preview**, including a **line-art (edge-detection) conversion mode** → edit the result with basic tools (selection, character replace, alignment, fill) → **Save as a `.txt` file** (filename retains the source image's name) and/or Insert at Cursor as today. The user can also **open an existing `.txt` ASCII file into the editor** to tweak it (not only freshly-converted output); if a re-convert would discard manual edits, the Studio **warns first**. The editable canvas supports **⌘Z / ⌘⇧Z undo/redo** for character-level edits. All conversion runs on `Task(priority: .userInitiated)` (SR-4, matching the current converter) and oversized images are scaled before conversion (SR-3). Deleting the Studio's persisted state still launches cleanly.

## UI / UX
**From floating panel → dockable column panel.** Today the Studio is an `NSPanel` summoned by ⌘⌥A that floats over the window and is not part of the layout. After this refactor it becomes a first-class **column panel** carrying the standard Sputnik chrome (`ASCII` badge, drag handle, close ✕). Consequences for UX:
- It sits in a resizable column beside the editor instead of obscuring it, can be dragged/re-tabbed like the Markdown/HTML/PDF panels, and **persists across relaunch** via layout state (the floating panel does not).
- The ⌘⌥A / Format → ASCII Studio trigger is re-pointed to **open or raise the panel** rather than show the floating window (must not regress ISS-041).

**Two tabs retained:** `Image → ASCII` and `Library` (migrated as-is).

**Adjustments use a disclosure, not an always-open stack.** Because the panel can now be dragged narrow (a column is narrower than the old 480 pt floating window), the Image → ASCII controls are grouped so the panel stays usable at small widths:
- **Always visible:** Import, Width, Style, Invert.
- **Collapsed under an "Adjustments" disclosure (default closed):** Brightness, Contrast, Dither.
This keeps the common path one glance away and tucks the new fine-tuning controls behind one click. Decision recorded 2026-06-12 (preferred over an always-open control stack for narrow-column legibility).

**Conversion mode — luminance vs line-art.** A mode control selects between the existing **luminance ramp** (density characters) and a new **line-art (edge-detection)** mode that maps detected edges to line glyphs (`/ \ | _ -`). It sits with Style in the always-visible row (mode changes the whole character vocabulary, so it is not buried in the disclosure).

**Editable canvas + edit toolbar.** The preview area changes from read-only (`textSelection` only) to an **editable character grid** with a small edit toolbar above it (Select / Replace character / Align / Fill). This is the largest single UX change.

**Open existing ASCII for editing.** Beyond image import, an **Open .txt…** action loads an existing ASCII file straight into the editable canvas, so hand-made or previously-saved art can be tweaked — the editor is two-way, not convert-only.

**Edit safety — warn before discarding edits + undo/redo.** If the canvas has manual edits and the user changes a conversion setting (width / style / mode / brightness / contrast / dither / new import) that would re-convert and overwrite them, the Studio **shows a confirmation first** ("Re-converting will discard your edits. Continue?"). The editable canvas also supports **⌘Z / ⌘⇧Z** for character-level edits (an `UndoManager` instance scoped to the Studio view). Decision recorded 2026-06-12 (warn-on-discard guard + undo/redo both in scope).

**Action bar:** `Open .txt…` (new) and `Save as .txt…` (new) alongside `Insert at cursor` (retained).

> **Related plan:** the basic/advanced split of the ASCII *Help* system and "More Context" was moved to its own plan — `2026-06-12 9.2 ASCII Help basic-advanced taxonomy.md` (modules 9.2 + 2.7). It shares no code with this Studio refactor.

## Steps

- [x] 1. **Create the `10 ASCII Studio` Swift package module**
   What: Scaffold `10 ASCII Studio/` with `Sources/`, `Tests/`, `Package.swift`; add to the root workspace and depend on `ResourcesModule` (for the bundled library) as `TextEditorModule` does today.
   Why: A dedicated module gives the Studio a specialised, dockable home and keeps creative tooling out of the Text Editor (SR-1). It must reuse the existing resource-bundling fix (ISS-045), not re-invent it.

- [x] 2. **Register a dockable Studio panel in Foundation**
   What: Add a `.asciiStudio` case to `PanelID`; wire it into `DynamicPanelLayout`/routing and `PersistenceService`. Re-point the existing ⌘⌥A / Format → ASCII Studio trigger (from `EditorCommandHandling.showASCIIStudio()`, ISS-041) to open/raise the panel instead of the floating `NSPanel`.
   Why: The Studio is currently an `NSPanel` singleton — making it a first-class dockable panel requires Foundation registration. **Foundation touch.** Must not regress the working ISS-041 trigger.

- [x] 3. **Migrate existing Studio files from 3.3 into module 10**
   What: Move `ASCIIStudioPanel.swift`, `ASCIIStudioView.swift`, `ImageToASCIIConverter.swift`, and `ASCIILibraryBrowser.swift` into `10 ASCII Studio/Sources/`. **Keep** Tier-1 `ASCIIArtLanguageProvider.swift` and `BlockCompletion.swift` in `3 Text Editor/3.3` (basic box-drawing stays in the editor).
   Why: These files already implement import, conversion, live preview, presets, and library browse — migrating preserves working code (SR-1 boundary: basic in 3.3, studio in 10) rather than rebuilding it.

- [x] 4. **Resolve the duplicate ASCII-library systems**
   What: Reconcile `ASCIILibraryBrowser` (3.3 → 10; reads `Resources/ASCIILibrary/<category>/*.txt`) with the `ASCIILibrary` actor (9.1; `index.json`-based search). Pick one as the single source the Studio consumes; route the other's callers through it.
   Why: Two libraries violate SR-1 (single source of truth) and risk divergent content. Must be decided before the Library tab is migrated.

- [x] 5. **Extend the converter: brightness, contrast, dithering**
   What: Add `brightness`, `contrast`, and a `dither` option (e.g. Floyd–Steinberg) to `ImageToASCIIConverter.convert(...)` alongside the existing `width`/`invert`/`style` parameters. Surface these three controls in the **"Adjustments" disclosure** (default closed) per the UI / UX section — not in the always-visible control row.
   Why: These are the genuinely missing conversion controls from the feature table; everything else in "Conversion Settings" already exists. The disclosure keeps the panel legible when dragged to a narrow column.

- [x] 6. **Add a line-art (edge-detection) conversion mode**
   What: Add an edge-detection mode (e.g. Sobel/DoG via Core Image) that maps detected edges to line glyphs (`/ \ | _ -`) instead of the luminance density ramp — in a small `ASCIIEdgeDetector.swift` helper feeding `ImageToASCIIConverter`. Expose a mode control (Luminance / Line-art) in the always-visible row.
   Why: Line-art is a distinct advanced technique that produces drawings rather than grayscale blobs; it is the most-requested "advanced" conversion beyond ramps. Stays on Apple imaging APIs (SR-5).

- [x] 7. **Add the ASCII editor, basic editing tools, and the warn-before-discard guard**
   What: New `ASCIIImageEditor.swift` — selection, character replace, alignment, and fill operating on the generated character grid. Render the **editable canvas + edit toolbar** described in the UI / UX section (replacing today's read-only `textSelection`-only preview). Track a `hasManualEdits` flag; before any re-convert (settings change / mode change / new import) **show a confirmation** if edits would be lost. Wire an `UndoManager` to the canvas so **⌘Z / ⌘⇧Z** undo/redo character-level edits.
   Why: No editing exists today (output is insert-only); this is the core new differentiator. The warn guard and undo stack together are the data-loss safeguards.

- [x] 8. **Open and edit existing `.txt` ASCII files**
   What: Add an **Open .txt…** action (`NSOpenPanel`) that loads an existing ASCII text file directly into the editable canvas, bypassing image conversion. The loaded art is editable and exportable like converted output.
   Why: Makes the editor two-way — hand-made or previously-saved ASCII can be reopened and tweaked, not just freshly-converted images.

- [x] 9. **Add the `ASCIIArt` data model and reconcile `ASCIIStyle`**
   What: Add `ASCIIArt.swift` (`Sendable`); introduce `ASCIIStyle` only if it adds beyond the existing `ImageToASCIIConverter.RampStyle` — otherwise extend `RampStyle` rather than duplicate it.
   Why: A typed model carries content/source/style/metadata for the editor and exporter; duplicating the existing `RampStyle` would re-introduce the SR-1 problem from step 4.

   ```swift
   struct ASCIIArt: Sendable {
       let id: UUID
       var title: String
       var asciiContent: String
       var sourceImageURL: URL?
       var style: ImageToASCIIConverter.RampStyle
       var width: Int
       var createdAt: Date
       var tags: [String]
   }
   ```

- [x] 10. **Add file export (Save as `.txt`)**
   What: New `ASCIIExporter.swift` using `NSSavePanel`; the saved `.txt` **retains the source image's filename** (no stored back-reference). Keep the existing "Insert at Cursor" path intact.
   Why: Today the Studio can only insert at the cursor; saving to a file is a missing capability and matches the resolved open-question on linkage.

- [x] 11. **Expand style presets (optional)**
   What: Add presets beyond Block/Minimal/Braille if useful, via the existing `RampStyle` enum.
   Why: Low-cost artistic variety; explicitly optional since three presets already ship.

- [x] 12. **Add tests**
   What: Unit tests for the extended converter (deterministic brightness/contrast/dither output and edge-detection mode), the data model, the exporter (filename-retention rule), and the open-`.txt` round-trip; migrate any existing converter tests into module 10.
   Why: Locks in the new conversion math, the round-trip, and the filename rule against regressions.

## Risks and Constraints
- **Foundation touch (SR-1):** new `PanelID` case + layout/persistence wiring; re-point the ISS-041 trigger without breaking it.
- **Migration risk:** moving four files across module boundaries can break imports/`Bundle.resourcesModule` paths (ISS-045) — verify the library still loads from the bundle after the move.
- **Library duplication (SR-1):** `ASCIILibraryBrowser` vs `ASCIILibrary` actor must converge to one source (step 4) before the Library tab ships in module 10.
- **Module boundary:** basic box-drawing (`ASCIIArtLanguageProvider`, `BlockCompletion`, "Tier 1") **stays in 3.3**; only the advanced Studio ("Tier 2") moves to module 10.
- **Related plan:** the basic/advanced Help taxonomy (9.2 + 2.7) is now a separate plan — `2026-06-12 9.2 ASCII Help basic-advanced taxonomy.md`. Its advanced topics describe this plan's Studio features, so they read most accurately once these land.
- **Terminology:** user-facing labels are **basic / advanced**; the module guide's "Tier 1 / Tier 2" are the same concepts (basic = Tier 1, advanced = Tier 2).
- **SR-3 / SR-4:** scale large images before conversion; keep conversion on `Task(priority: .userInitiated)` as the current converter already does.
- **SR-5:** stay on Apple imaging APIs (`CGBitmapContext`/`CGImage`), as the existing converter does — no third-party packages.
- **Resolved decisions (from open questions + 2026-06-12 review):**
  - Converted `.txt` retains the original image's filename; no stored image reference.
  - **Edit safety:** re-converting over manual edits **warns first** (confirmation), rather than silent discard. Character-level edits also support **⌘Z / ⌘⇧Z** via `UndoManager` (promoted from deferred — both safeguards are in scope).
  - **Library stays read-only:** no user-writable "save to personal library" — the ASCII Library remains a curated, bundle-shipped asset.
  - Colour/ANSI art — **future placeholder**, out of scope.
  - Dedicated `.ascii` file type — **future placeholder**; use `.txt` for now.
  - Clipboard copy / PNG / HTML export — considered, **not in this plan** (insert + save `.txt` only).

## Files Affected
*New (module 10):*
- `10 ASCII Studio/Package.swift` — new module manifest (depends on `ResourcesModule`)
- `10 ASCII Studio/Sources/ASCIIImageEditor.swift` — **new** editing tools + `hasManualEdits` / warn-before-discard
- `10 ASCII Studio/Sources/ASCIIEdgeDetector.swift` — **new** line-art (edge-detection) mode helper
- `10 ASCII Studio/Sources/ASCIIArt.swift` — **new** data model
- `10 ASCII Studio/Sources/ASCIIExporter.swift` — **new** save-to-`.txt` + open-`.txt` loader
- `10 ASCII Studio/Sources/ASCIIStudioCoordinator.swift` — **new** insert/route into document
- `10 ASCII Studio/Tests/` — converter / edge-detection / model / exporter / open-round-trip tests

*Migrated from `3 Text Editor/3.3 ASCII art/` (already exist):*
- `ASCIIStudioPanel.swift`, `ASCIIStudioView.swift`, `ImageToASCIIConverter.swift` (extended in step 5), `ASCIILibraryBrowser.swift` (reconciled in step 4)

*Foundation:*
- `2 Foundation/2.4 UI and UX/PanelID.swift` — add `.asciiStudio` case **(Foundation)**
- `2 Foundation/2.x …` — layout/routing/persistence wiring + re-point ISS-041 trigger **(Foundation)**

*Stays in place:*
- `3 Text Editor/3.3 ASCII art/ASCIIArtLanguageProvider.swift`, `BlockCompletion.swift` — basic (Tier 1), unchanged
- `Package.swift` (root) — register module 10
- `9 Resources/Sources/9.1 ASCII Library/*` — touched only if chosen as the single library source (step 4)

## Closeout
- [x] Re-read the Purpose statement — outcome matches (dockable panel, extended converter, editor tools, file export)
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated — module 10 guide created; 3.3 guide updated (Tier-2 moved out, Tier-1 retained) — 2026-06-12
- [ ] Changes committed: `[10 ASCII Studio] Deepen ASCII Studio`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
