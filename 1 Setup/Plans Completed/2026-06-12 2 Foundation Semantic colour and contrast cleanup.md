---
plan: Semantic colour and contrast cleanup
module: 2 Foundation (2.4 UI and UX)
created: 2026-06-12
status: pending
related_issues: none
---

## Purpose
Replace the remaining hard-coded literal RGB backgrounds (editor, terminal) in `SputnikColor` with appearance- and accessibility-aware definitions so they adapt to the Increase Contrast setting and stay consistent with the otherwise-semantic palette.

## Success Condition
- Toggling **Increase Contrast** in System Settings visibly adjusts the editor and terminal backgrounds (higher-contrast variant) rather than leaving the fixed pastel values.
- Editor/terminal backgrounds still look correct in both light and dark mode, with no visible regression from current appearance.
- No literal `Color(red:green:blue:)` background constants remain in `SputnikColor` except where a deliberate, documented brand value is required.

## Steps

- [ ] 1. **Inventory hard-coded colour literals**
   What: List every `Color(red:…)` / fixed light-dark pair in `SputnikColor.swift` (editorBackground, terminalBackground, terminalForeground, etc.) and classify each as "should be semantic" vs "intentional brand value".
   Why: The cleanup must distinguish accidental literals from deliberate ones before changing anything.

- [ ] 2. **Introduce contrast-aware dynamic providers**
   What: For each "should be semantic" colour, replace the literal pair with an `NSColor(name:)` dynamic provider that branches on both `appearance` (light/dark) **and** the increased-contrast appearance trait, returning a higher-contrast variant when requested.
   Why: The existing dynamic-provider pattern (already used elsewhere in the file) extends naturally to read the contrast trait, satisfying SR-5 (native API) with no new dependency.

- [ ] 3. **Prefer system semantic colours where appropriate**
   What: Where a system colour fits (e.g. `textBackgroundColor` for editor surfaces), use it instead of a bespoke provider so the app inherits Apple's contrast handling for free.
   Why: System semantic colours already encode contrast/appearance behaviour — fewer bespoke values to maintain.

- [ ] 4. **Keep tuned values for the terminal where needed**
   What: If the terminal needs specific tuned backgrounds for ANSI legibility, retain them but route through the contrast-aware provider with documented light/dark/high-contrast triples.
   Why: Terminal readability is a hard requirement; this preserves intent while still honouring Increase Contrast.

- [ ] 5. **Verify across the appearance matrix**
   What: Check editor + terminal in light, dark, and each with Increase Contrast on; confirm no regression and a clear contrast change.
   Why: Satisfies the Success Condition across the four relevant system states.

## Risks and Constraints
- SR-1: all colour changes stay inside Foundation's `SputnikColor`; no module defines its own background.
- SR-5: use only `NSColor`/`NSAppearance` APIs for the contrast branch — no third-party colour handling.
- Low-risk, visual-only change, but a wrong high-contrast value could hurt legibility — eyeball every state.
- Coordinate with the Differentiate-Without-Color work in the Accessibility plan to avoid conflicting edits to the same file.

## Files Affected
- `2 Foundation/2.4 UI and UX/SputnikColor.swift` — replace literal backgrounds with contrast-aware providers

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (light/dark × Increase Contrast matrix)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation] Semantic colour and contrast cleanup`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
