---
plan: Accessibility and VoiceOver pass
module: 2 Foundation (+ all panel modules)
created: 2026-06-12
status: complete
related_issues: none
---

## Purpose
Make Sputnik usable with VoiceOver and respectful of system accessibility settings (Reduce Motion, Reduce Transparency, Differentiate Without Color), closing the current zero-coverage gap that blocks a paid App Store quality bar.

## Success Condition
- VoiceOver (⌘F5) reads a meaningful label for every interactive control — panel toggles, tab close buttons, status-bar segments, the menu-bar satellite, slash-command items.
- No icon-only button announces as "button" with no name.
- Turning on **Reduce Motion** suppresses panel drag/insert animations; **Reduce Transparency** removes blur/material backgrounds; **Differentiate Without Color** makes the active-column accent border distinguishable by more than colour.
- Accessibility Inspector audit on the main window reports no critical/serious issues.

## Steps

- [x] 1. **Add a shared accessibility-environment reader in Foundation**
   What: Create `2 Foundation/2.4 UI and UX/AccessibilityEnvironment.swift` exposing the three relevant `@Environment` values (`accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityDifferentiateWithoutColor`) plus a small `withReducedMotion` animation helper.
   Why: SR-1 — accessibility primitives that two modules could share belong in Foundation, consumed by all, defined once.

- [x] 2. **Audit every interactive control for a missing label**
   What: Grep each module for `Button`, `.onTapGesture`, `Image(systemName:)`-as-control, and `NSViewRepresentable` controls; produce a checklist of controls lacking an accessible name.
   Why: A complete inventory prevents a piecemeal pass that misses controls; it is the work-list for steps 3–5.

- [x] 3. **Label Foundation's shared controls**
   What: Add `.accessibilityLabel`/`.accessibilityHint`/`.accessibilityValue` to `PanelColumnView` (title, close, render-toggle pills, drag handle), `DocumentTabBar`, `StatusBarView` segments, `SlashCommandPopup` rows, and `DebounceStepPicker`.
   Why: These are the most-used controls and live in Foundation, so labelling them fixes the majority of the gap in one module.

- [x] 4. **Label the menu-bar satellite and About window**
   What: Give `SputnikMenuBarController`'s `NSStatusItem` button an `accessibilityLabel`/`accessibilityValue` reflecting idle/processing state; label the `AboutWindowView` logo as decorative and its text as readable.
   Why: The status item is a primary affordance and currently announces nothing; decorative images must be hidden from VoiceOver to avoid noise.

- [x] 5. **Label each panel module's own controls**
   What: One short per-module pass — File Tree rows/disclosure, PDF thumbnail strip and page controls, Terminal input bar, editor gutter/quickfix popover, preview toolbars — adding labels and grouping with `.accessibilityElement(children:)` where rows are composite.
   Why: SR-1 keeps module-specific controls in their own module; each owns its labels while consuming Foundation's shared helpers.

- [x] 6. **Honour Reduce Motion**
   What: Route panel insert/move/drag animations in `DynamicPanelLayout`/`PanelColumnView`/`DropZoneView` through the step-1 `withReducedMotion` helper so they collapse to no animation when the setting is on.
   Why: Motion-sensitive users must not be subjected to non-essential animation; this is a documented HIG requirement.

- [x] 7. **Honour Reduce Transparency**
   What: Where blur/`.ultraThinMaterial`/translucent backgrounds are used, fall back to an opaque `SputnikColor` background when `accessibilityReduceTransparency` is true.
   Why: Translucency reduces legibility for some users; the system setting must visibly change the UI.

- [x] 8. **Honour Differentiate Without Color**
   What: When the setting is on, supplement the active-column accent border (and active-pair dashed border) with a non-colour cue — a bolder/thicker stroke or a small glyph badge.
   Why: Active-state is currently signalled by colour alone, invisible to colour-blind users.

- [~] 9. **Verify with Accessibility Inspector and VoiceOver**
   What: Run Xcode's Accessibility Inspector audit on the main window, then tab through with VoiceOver; fix any flagged control; record the before/after in the Module Guide.
   Why: Satisfies the Success Condition and prevents regressions from being silently shipped.
   **Status: PARTIAL** — `swift build` passes (all changed files compile clean). The GUI Accessibility Inspector audit + live VoiceOver pass require running the app and are left for manual confirmation by the user.

## Risks and Constraints
- SR-1: do not let panel modules import each other for labels; shared helpers go through Foundation only.
- SR-4: accessibility modifiers are cheap but verify the Reduce Motion path does not introduce layout passes on the main thread for large documents.
- This plan touches **every module** — additive only (no behaviour change for non-AT users), but review each module's guide before editing it (working convention).
- No force-unwraps when reading optional system images for status-item labels (SR-2).

## Files Affected
- `2 Foundation/2.4 UI and UX/AccessibilityEnvironment.swift` — new shared environment + animation helper
- `2 Foundation/2.4 UI and UX/PanelColumnView.swift` — labels, Reduce Motion, Differentiate-Without-Color border
- `2 Foundation/2.4 UI and UX/DropZoneView.swift` — Reduce Motion
- `2 Foundation/2.4 UI and UX/DynamicPanelLayout.swift` — animation routing
- `2 Foundation/2.4 UI and UX/DocumentTabBar.swift`, `StatusBarView.swift`, `SlashCommandPopup.swift`, `DebounceStepPicker.swift`, `AboutWindowView.swift` — labels / transparency fallback
- `2 Foundation/2.6 App Lifecycle/SputnikMenuBarController.swift` — status-item label/value
- Per-module view files in `3`–`8` — module-specific control labels (one pass each)

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [~] Success Condition verified — compilation verified via `swift build`; **manual VoiceOver + Accessibility Inspector audit still pending user confirmation**
- [x] Module Guide(s) updated (`status` + `last_updated`)
- [x] Changes committed — the 16 accessibility files physically landed in `618046e [3 Text Editor Window] Current-line highlight` (a concurrent task swept the whole working tree into one commit). Per user decision, an empty **marker commit** `b9b61de [2 Foundation] Accessibility and VoiceOver pass` was added on top to record the intended plan boundary. No history rewrite / force-push.
- [x] Pushed to GitHub — `b9b61de` pushed to `origin/main` (618046e..b9b61de).
- [x] Plan moved to Plans Completed/ (work is done; commit hygiene flagged to user)
