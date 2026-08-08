---
plan: Current-line highlight
module: 3 Text Editor Window (3.1 Text)
created: 2026-06-12
status: complete
related_issues: none
---

## Purpose
Add a subtle current-line highlight to the text editor — a semi-transparent tint on the line containing the cursor (and optionally its gutter line number) — to help the user's eye lock onto the active editing position instantly, toggled by a Settings flag.

## Success Condition
1. With a text file open, the line containing the blinking cursor is filled with a subtle highlight colour.
2. Moving the cursor (by typing, arrow keys, or mouse click) moves the highlight to the new current line in real time.
3. The highlight is visible in all editor modes (plain text, Markdown, HTML, ASCII).
4. A toggle in Settings (default: `true`) enables/disables the highlight; toggling off immediately removes the highlight.
5. The highlight respects light/dark mode and the editor's background colour.

## Steps

- [x] 1. **Add `currentLineHighlightEnabled` to `SettingsStore`**
   What: Add `public var currentLineHighlightEnabled: Bool = true` to `SettingsStore` (Foundation 2.3), a `DefaultsKey` entry `"sputnik.settings.currentLineHighlight"`, and a `setCurrentLineHighlightEnabled(_:)` mutator.
   Why: The feature must be user-togglable and persisting the toggle follows the existing SettingsStore pattern (every other editor affordance does the same).

- [x] 2. **Add load block to `SettingsLoader`**
   What: In `SettingsLoader.swift` (Foundation 2.5), add an `if let saved: Bool` block for the new key after the existing editor settings section.
   Why: Without this, the setting is never restored from UserDefaults across launches.

- [x] 3. **Override `drawBackground(in:)` in `EditorTextView`**
   What: Override `drawBackground(in:)` on `EditorTextView` (3.1 Text). When `currentLineHighlightEnabled` is true, use `NSLayoutManager` to get the line fragment rect for the insertion point's current glyph index, then fill that rect with a subtle highlight colour (a semi-transparent accent tint, derived from the editor's background colour via a brightness shift or a fixed `NSColor.selectedTextBackgroundColor.withAlphaComponent(0.15)`).
   Why: `drawBackground(in:)` is the standard AppKit hook for adding a highlight behind text without interfering with text rendering. Drawing only when enabled keeps the toggle path cheap.

- [x] 4. **Track cursor-movement (selection-change) events to trigger redraw**
   What: Implement `textViewDidChangeSelection(_:)` in `EditorView.Coordinator`. After the super call, call `textView.needsDisplay = true` to trigger `drawBackground(in:)` on the next display cycle. Cache the previous line rect to minimise invalidation area (set `needsDisplayInRect(_:)` on just the old and new line rects).
   Why: The highlight must follow the cursor in real time. `textViewDidChangeSelection` fires on every cursor move, arrow key, and mouse click. Invalidating only the affected rects avoids redrawing the entire text view on every keystroke.

- [x] 5. **Wire the setting toggle through `EditorView`**
   What: In `EditorView.updateNSView`, propagate `settings.currentLineHighlightEnabled` to the `EditorTextView` (add a `var currentLineHighlightEnabled: Bool = true` property on `EditorTextView`). When the setting changes, set `textView.needsDisplay = true` to show or clear the highlight.
   Why: The text view needs to read the currently active toggle value. Propagating through `updateNSView` ensures the toggle takes effect immediately when the user changes it in Settings.

- [x] 6. **Add gutter current-line highlight in `LineNumberRulerView`**
   What: In `LineNumberRulerView.drawHashMarksAndLabels(in:)`, after drawing the line number text, detect whether the drawn line is the current line (by comparing its character range against the insertion point). If so, fill the label's background rect — or change the label's foreground colour — to a highlighted variant. Gate this on the same current-line highlight setting, passed in as a property.
   Why: The feature spec calls out "and/or its gutter line number" — highlighting the gutter number reinforces the visual lock. The existing ruler already iterates line-by-line, so the incremental cost is one range comparison per visible line.

- [x] 7. **Wire `currentLineHighlightEnabled` into `LineNumberRulerView`**
   What: Add a `var highlightCurrentLine: Bool = true` property to `LineNumberRulerView`. Set it from `EditorView.updateNSView` via `(scrollView.verticalRulerView as? LineNumberRulerView)?.highlightCurrentLine = settings.currentLineHighlightEnabled`.
   Why: `LineNumberRulerView` is an `NSRulerView` subclass created in `EditorView.makeNSView` — it does not have access to `SettingsStore` directly. This follows the existing pattern of injecting values from the `NSViewRepresentable`.

- [x] 8. **Update the Module Guide for 3.1 Text**
   What: Add "current-line highlight" to the Purpose section, add a brief note to the Technical Summary, and add the new/changed source files to the Source Files table. Set `last_updated: 2026-06-12`.
   Why: The guide must reflect the module's actual capability.

## Risks and Constraints
- **Performance:** Drawing the highlight rect on every selection change must not regress typing latency. Caching the previous line rect and invalidating only the old/new rects (step 4) mitigates this. The highlight is a single `NSRectFill` — negligible cost.
- **Dark mode:** The highlight colour must be legible in both light and dark appearances. Using `selectedTextBackgroundColor.withAlphaComponent(0.15)` adapts to the current appearance automatically. Alternatively, a computed colour from the editor background keeps it harmonious.
- **No Foundation changes beyond SettingsStore:** The feature stays entirely within module 3.1 (text view drawing) and adds one field to Foundation 2.3. No cross-module routing changes needed.
- **Toggle interaction:** The setting toggle is purely in Settings (no dedicated toolbar button). This matches the "low cost" implementation note and keeps scope minimal.

## Files Affected
- `2 Foundation/2.3 Settings/SettingsStore.swift` — Add `currentLineHighlightEnabled` property, `DefaultsKey`, and mutator
- `2 Foundation/2.5 Persistence/SettingsLoader.swift` — Add load block for the new key
- `3 Text Editor/3.1 Text/EditorTextView.swift` — Override `drawBackground(in:)` for current-line rect; add `currentLineHighlightEnabled` property
- `3 Text Editor/3.1 Text/EditorView.swift` — Add `textViewDidChangeSelection` to Coordinator; wire setting to text view and ruler via `updateNSView`
- `3 Text Editor/3.1 Text/LineNumberRulerView.swift` — Highlight gutter number for the current line; add `highlightCurrentLine` property
- `1 Setup/Module Guides/3 Text Editor Window/3.1 Text/guide.md` — Document the new feature

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (build clean, logic reviewed)
- [x] Module Guide(s) updated (`status: stable`, `last_updated: 2026-06-12`)
- [ ] Changes committed: `[3 Text Editor Window] Current-line highlight`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
