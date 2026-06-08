---
plan: Implement Text Editor module source
module: 3 Text Editor Window
created: 2026-06-08
status: pending
related_issues: ISS-004
---

## Purpose
Write the Swift source for the Text Editor module (3) — the base `NSTextView` editing surface (line numbers, syntax highlighting, undo/redo, external file-watching, find/replace, save-as, auto-save + crash recovery, file-size/encoding protection) plus its four language tiers: Markdown (3.2), ASCII art with Studio panel (3.3), HTML (3.4), and spelling/grammar (3.5).

> **Scope note (per user decision):** This plan only *authors `.swift` files* into the existing `3 Text Editor/` folders. It does **not** create an Xcode project, target, or build system — you will do that in Xcode later. No compile step is in scope; every file is written Swift-6-strict-concurrency-clean *by inspection*.

> **Depends on Foundation (skill Rule — module-2 flag):** the editor consumes Foundation contracts the *"Implement Foundation module source"* plan authors but which are **not yet committed**: `DebounceTimer` (2.7), `SettingsStore` (2.3), `InterPanelRouter` (2.1, for "Render as HTML"), `AppState` (2.2), `FileType`/`SputnikAlert` (2.1/2.4). Execute Foundation first or those references dangle. The editor reaches other panels (Markdown Preview 4, HTML Preview 8) **only** through the Foundation router protocol — never directly (SR-1).

## Success Condition
All true by inspection (no build in scope):

1. Every "Key type" named in guides 3.1–3.5 exists as a Swift file in the matching `3 Text Editor/3.x …/` folder, one responsibility per file (**SR-6**).
2. **Shared editor utilities defined once in 3.1**: `GhostTextOverlay` and `SyntaxHighlighter` live in `3.1 Text/` and are *referenced* by 3.2/3.3/3.4 — never re-implemented or copied (the guides state this explicitly).
3. **No `DebounceTimer` re-implementation**: all four language tiers import the Foundation 2.7 `DebounceTimer` (SR-1 / SR-5).
4. **SR-3 (RAM protection)**: `EncodingGuard` refuses to open binary/over-sized files *before* loading into `NSTextStorage`; nothing reads a whole oversized file into memory.
5. **SW-3**: AppKit (`NSTextView`/`NSRulerView`/`NSPanel`) is used via `NSViewRepresentable`/`NSPanel` with a doc-comment justifying it (heavy text view — the explicit SW-3 exception); SwiftUI is used everywhere else (toolbar, search bar, Studio content).
6. **SW-1/SW-4/SR-2**: file I/O on `.userInitiated`, highlighting on `.utility`, crash serialise on `.background`; all `NSTextStorage` mutations on `@MainActor`; no force-unwraps; `///` doc-comments throughout.
7. **SW-2**: the `FileWatcher` presenter and every long-lived debounce/highlight `Task` capture `[weak self]`.
8. **Ghost-text contract**: suggestions accept on **Tab**, clear on any other keypress, across 3.2/3.3/3.4 via the single `GhostTextOverlay`.
9. **Routing boundary (SR-1)**: "Render as HTML" (3.4) calls the Foundation 2.1 `InterPanelRouter` protocol to open module 8 — the editor does not call module 8 directly.
10. **Gating guards present**: `HTMLDocTypeGuard` (3.4), `SpellCheckFileTypeGuard` (3.5) gate their features exactly as the guides specify; ISS-004 settings gaps are worked around with local defaults, documented at the seam.

## Steps

- [ ] 1. **Editor state core — `EditorMode` + `EditorViewModel`**
   What: `3.1 Text/EditorMode.swift` (enum `.plainText/.markdown/.html/.asciiArt`). `3.1 Text/EditorViewModel.swift` — `@MainActor @Observable` class owning the open file URL, dirty flag, undo/redo stack, current `EditorMode`, and the `htmlModeActive`/`spellCheckActive` flags that 3.4/3.5 set.
   Why: Every other file in the module reads or mutates this view model; defining it first gives the rest real types to bind to. Centralising the mode + gating flags here (not scattered across sub-modules) honours SR-1's "module owns its state" and matches the guides, which explicitly place these flags in `EditorViewModel`.

- [ ] 2. **File-load protection — `EncodingGuard`**
   What: `3.1 Text/EncodingGuard.swift` — validates file size against a cap and detects text vs binary/encoding before any load; returns a `Result`/throws so the caller refuses oversized or binary files (no partial in-memory load).
   Why: SR-3 + spec 3.1.8 — this is the RAM-exhaustion guard and must run *before* `NSTextStorage` is populated. Writing it early lets the load path (next steps) depend on it.

- [ ] 3. **Text surface — `EditorTextView` + `LineNumberRulerView`**
   What: `3.1 Text/EditorTextView.swift` — an `NSTextView` subclass handling key events (Tab acceptance hook for ghost text, ⌘F toggle). `3.1 Text/LineNumberRulerView.swift` — an `NSRulerView` drawing the line-number gutter.
   Why: Spec 3.1.1 (line numbers) + the editing surface itself. SW-3 justifies raw AppKit here (heavy text view). Splitting the gutter from the text view respects SR-6 (distinct responsibilities).

- [ ] 4. **SwiftUI bridge — `EditorView`**
   What: `3.1 Text/EditorView.swift` — the `NSViewRepresentable` wrapping `EditorTextView` in its scroll view + ruler, binding to `EditorViewModel`, with a doc-comment stating the SW-3 justification at the call site.
   Why: SW-3 requires the AppKit bridge to be a thin, documented boundary; this file is that boundary and the panel's public entry point the 2.4 layout drops into a slot.

- [ ] 5. **Shared editor utilities — `SyntaxHighlighter` + `GhostTextOverlay`**
   What: `3.1 Text/SyntaxHighlighter.swift` — applies `NSTextStorage` colour attributes for the active `EditorMode` (skipped for `.plainText`) on `Task(priority: .utility)`, writing back on `@MainActor`. `3.1 Text/GhostTextOverlay.swift` — renders an inline suggestion as a greyed secondary `NSTextStorage` attribute after the cursor; `show(_:)`/`clear()`; accepts on Tab, clears otherwise.
   Why: The guides mandate these live in 3.1 and are shared by 3.2/3.3/3.4 (Success Condition 2). Authoring them once here is the SR-1 single-source guarantee that prevents per-tier duplication.

- [ ] 6. **External-change watching — `FileWatcher`**
   What: `3.1 Text/FileWatcher.swift` — an `NSFilePresenter` (MR-2) watching the open file; on an external change it prompts reload-or-keep via a Foundation `SputnikAlert`. Presenter callbacks capture `[weak self]` and hop to `@MainActor`.
   Why: Spec 3.1.4; MR-2 forbids timer-polling the FS. SW-2: the presenter is a long-lived observer and is the leak risk here.

- [ ] 7. **Auto-save + crash recovery — `CrashRecoveryStore`**
   What: `3.1 Text/CrashRecoveryStore.swift` — serialises editor text to a temp cache on `Task(priority: .background)` on each significant change, via the Foundation `PersistenceService.writeRecovery(for:content:)` seam; retries on next change if a write fails.
   Why: Spec 3.1.7; SR-1 routes durable writes through Foundation persistence (no direct `FileManager` here). `.background` QoS keeps serialisation off the typing path (SR-4).

- [ ] 8. **Find/replace — `SearchController` + `SearchBarView`**
   What: `3.1 Text/SearchController.swift` — owns visible/hidden state (⌘F), search/replace terms, current match index, and match-highlight ranges in `NSTextStorage`. `3.1 Text/SearchBarView.swift` — the SwiftUI slide-in Find/Replace bar bound to it.
   Why: Spec 3.1.5. Keeping match-state logic (controller) separate from its SwiftUI presentation (bar) respects SR-6; the bar is SwiftUI per SW-3 (no raw-AppKit need).

- [ ] 9. **Markdown tier (3.2) — `MarkdownLanguageProvider`**
   What: `3.2 Markdown Language/MarkdownLanguageProvider.swift` — inspects cursor context (heading, list, link, fenced code) and returns a suggestion string on `Task(priority: .utility)`; debounced via Foundation 2.7 `DebounceTimer`; renders through the shared `GhostTextOverlay`.
   Why: Spec 12. Reuses 3.1's overlay and 2.7's debounce (Success Conditions 2–3), adding only the Markdown-specific logic this tier owns.

- [ ] 10. **HTML tier (3.4) — guard, provider, render command**
   What: `3.4 HTML Langugage/HTMLDocTypeGuard.swift` (scan first ~512 bytes case-insensitively for `<!DOCTYPE html>`, sets `htmlModeActive`), `HTMLLanguageProvider.swift` (tag/attribute completions, only when `htmlModeActive`), `RenderAsHTMLCommand.swift` (File-menu action, ⌘⌥P, enabled only in HTML mode, calls the Foundation 2.1 `InterPanelRouter` to open module 8).
   Why: Spec 11. The 512-byte cap bounds scan time on huge files (SR-3/SR-4); routing through the 2.1 protocol keeps the editor decoupled from module 8 (SR-1, Success Condition 9).

- [ ] 11. **Spelling/grammar tier (3.5) — guard, checker, quickfix**
   What: `3.5 Spelling and Grammar Checking/SpellCheckFileTypeGuard.swift` (allow `.txt`/`.md`, block others, sets `spellCheckActive`), `SpellingGrammarChecker.swift` (debounced `NSSpellChecker` wrapper writing red/green underline attributes), `QuickfixPresenter.swift` (right-click `NSMenu` of corrections → `NSTextStorage` replace).
   Why: Spec 9. Uses native `NSSpellChecker` (SR-5, no dependency); all `NSSpellChecker`/attribute work on `@MainActor` (AppKit requirement). Locale gap from ISS-004 is worked around by falling back to the system default locale, documented at the call site.

- [ ] 12. **ASCII tier 1 — auto box-drawing (`ASCIIArtLanguageProvider` + `BlockCompletion`)**
   What: `3.3 ASCII art/ASCIIArtLanguageProvider.swift` (detect box-drawing sequences/partial frames at cursor; return ghost char or block payload, debounced via 2.7) and `3.3 ASCII art/BlockCompletion.swift` (expand a partial pattern to a full frame on Tab).
   Why: Spec 10 (ghost text + block completion). Reuses the shared overlay and debounce; the auto tier needs no manual UI.

- [ ] 13. **ASCII tier 2 — Studio panel (`ImageToASCIIConverter`, `ASCIILibraryBrowser`, `ASCIIStudioPanel` + `ASCIIStudioView`)**
   What: `3.3 ASCII art/ImageToASCIIConverter.swift` (`NSImage` → `CGBitmapContext` at target width → per-pixel Rec.601 luminance `0.299R+0.587G+0.114B` → density-ramp character; invert + Block/Minimal/Braille ramps as a small co-located enum; runs on `.userInitiated`), `ASCIILibraryBrowser.swift` (lazily load bundled `.txt` clips from `9 Resources/ASCIILibrary/<category>/`, insert at cursor), `ASCIIStudioPanel.swift` (floating `NSPanel`, ⌘⌥A) + `ASCIIStudioView.swift` (SwiftUI two-tab content: Image→ASCII and Library).
   Why: Spec 10 (Studio). CoreGraphics conversion off the main thread (SR-4); lazy clip loading + graceful skip-on-missing (SR-3 + guide failure mode) means the currently-empty library folders degrade quietly rather than crash.

- [ ] 14. **Cross-file consistency + rules audit**
   What: Re-read all module-3 files together. Verify: shared `GhostTextOverlay`/`SyntaxHighlighter` referenced not duplicated (SC 2); every tier uses 2.7 `DebounceTimer` (SC 3); `EncodingGuard` gates loads (SC 4, SR-3); AppKit confined to text view/ruler/panel with SW-3 justification (SC 5); QoS tiers + `@MainActor` mutations + no `!` + `///` (SC 6); `[weak self]` on `FileWatcher`/Tasks (SC 7, SW-2); Tab-accept/clear ghost contract (SC 8); Render-as-HTML via 2.1 protocol (SC 9, SR-1). Confirm Foundation seam names match the Foundation plan; fix drift or note against ISS-004.
   Why: With no compiler in scope, this whole-set read is the only check that the ~25 files cohere and that the Foundation seams line up.

## Risks and Constraints
- **Hard dependency on the Foundation plan (uncommitted).** `DebounceTimer`, `SettingsStore`, `InterPanelRouter`, `AppState`, `SputnikAlert`, `PersistenceService` must exist; run Foundation first. No build target either way (user scope).
- **ISS-004 (Settings gaps).** Auto-save interval, debounce interval, suggestions-enabled toggle, ASCII trigger key, and spell-check locale are not defined in 2.3. This plan ships sensible local defaults at each seam and documents them; the real fix belongs in Foundation 2.3, not here (defining them in module 3 would violate SR-1).
- **ASCIILibrary content is empty.** The `9 Resources/ASCIILibrary/<category>/` folders exist but contain no `.txt` clips yet. Authoring clip content is out of scope (not Swift code); `ASCIILibraryBrowser` already degrades gracefully (guide failure mode) so this is non-blocking.
- **SW-3 must stay narrow.** AppKit is justified only for the text view, line-number ruler, and Studio `NSPanel`. The toolbar, search bar, and Studio tab content stay SwiftUI; each AppKit boundary carries a documented reason.
- **SW-2 leaks.** `FileWatcher` (long-lived presenter) and the per-keystroke debounce/highlight Tasks are the leak risks — `[weak self]` is mandatory and audited in Step 14.
- **Module is large (~25 files).** Build strictly bottom-up (state → guard → surface → utilities → tiers) so each file references already-authored types; the Step 14 audit is the in-scope substitute for a compiler.

## Files Affected
**3.1 Text**
- `3 Text Editor/3.1 Text/EditorMode.swift` — editing-mode enum
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — `@MainActor @Observable` editor state (URL, dirty, undo, mode, gating flags)
- `3 Text Editor/3.1 Text/EncodingGuard.swift` — size/encoding refusal before load (SR-3)
- `3 Text Editor/3.1 Text/EditorTextView.swift` — `NSTextView` subclass (key handling)
- `3 Text Editor/3.1 Text/LineNumberRulerView.swift` — `NSRulerView` line-number gutter
- `3 Text Editor/3.1 Text/EditorView.swift` — `NSViewRepresentable` bridge (SW-3 documented)
- `3 Text Editor/3.1 Text/SyntaxHighlighter.swift` — shared `NSTextStorage` colouriser (.utility)
- `3 Text Editor/3.1 Text/GhostTextOverlay.swift` — shared inline-suggestion overlay (Tab-accept)
- `3 Text Editor/3.1 Text/FileWatcher.swift` — `NSFilePresenter` external-change watcher (MR-2)
- `3 Text Editor/3.1 Text/CrashRecoveryStore.swift` — background recovery serialisation via 2.5
- `3 Text Editor/3.1 Text/SearchController.swift` — find/replace state + match ranges
- `3 Text Editor/3.1 Text/SearchBarView.swift` — SwiftUI slide-in Find/Replace bar

**3.2 Markdown Language**
- `3 Text Editor/3.2 Markdown Language/MarkdownLanguageProvider.swift` — Markdown ghost-text suggestions

**3.3 ASCII art**
- `3 Text Editor/3.3 ASCII art/ASCIIArtLanguageProvider.swift` — box-drawing detection (tier 1)
- `3 Text Editor/3.3 ASCII art/BlockCompletion.swift` — Tab-expand partial frame to full
- `3 Text Editor/3.3 ASCII art/ImageToASCIIConverter.swift` — Rec.601 luminance image→ASCII (+ ramp enum)
- `3 Text Editor/3.3 ASCII art/ASCIILibraryBrowser.swift` — lazy bundled clip browser + insert
- `3 Text Editor/3.3 ASCII art/ASCIIStudioPanel.swift` — floating `NSPanel` host (⌘⌥A)
- `3 Text Editor/3.3 ASCII art/ASCIIStudioView.swift` — SwiftUI two-tab Studio content

**3.4 HTML Langugage**
- `3 Text Editor/3.4 HTML Langugage/HTMLDocTypeGuard.swift` — 512-byte doctype gate
- `3 Text Editor/3.4 HTML Langugage/HTMLLanguageProvider.swift` — tag/attribute completions
- `3 Text Editor/3.4 HTML Langugage/RenderAsHTMLCommand.swift` — ⌘⌥P → 2.1 router → module 8

**3.5 Spelling and Grammar Checking**
- `3 Text Editor/3.5 Spelling and Grammar Checking/SpellCheckFileTypeGuard.swift` — .txt/.md gate
- `3 Text Editor/3.5 Spelling and Grammar Checking/SpellingGrammarChecker.swift` — `NSSpellChecker` underlines
- `3 Text Editor/3.5 Spelling and Grammar Checking/QuickfixPresenter.swift` — right-click correction menu

**Tracking / guides (closeout)**
- `1 Setup/References/Issues.md` — ISS-004 status note
- `1 Setup/Module Guides/3 Text Editor Window/3.1–3.5/guide.md` — `status` → active + `last_updated`

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (Step 14 inspection pass — all 10 points confirmed)
- [ ] ISS-004 reviewed — resolved in Foundation 2.3 or left Open with a note (do not silently close)
- [ ] Module Guides 3.1–3.5 updated (`status` + `last_updated`)
- [ ] Changes committed: `[3 Text Editor] Implement Text Editor module source`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
