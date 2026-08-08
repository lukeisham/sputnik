---
plan: Add Minimap
module: 2 Foundation (primary) · 3 Text Editor · 4 Markdown Preview · 8 HTML Preview
created: 2026-06-16
status: completed
related_issues: none (reuses ISS-063 scroll-sync, ISS-093/096 bridge-ownership infra)
---

> ⚠️ **Touches Foundation (module 2).** Per !GenerateAPlan Rule, this is flagged
> explicitly: changes to AppState/WindowState, SettingsStore, the View menu, and a new
> 2.4 UI primitive affect every consuming panel. The new primitive is additive (no
> existing Foundation type changes shape), which contains the blast radius.

## Purpose
Add a semi-transparent minimap on the trailing edge of the active content panel that gives
a visual overview of long documents for click-and-drag navigation — across the text editor,
Markdown preview, HTML preview, and JSON viewer.

## Success Condition
- `swift build` succeeds.
- **View ▸ Minimap** (⌃⌘5) toggles a minimap on the right edge of the active panel; the
  toggle reflects state with a checkmark.
- The minimap appears for all four panel types (plain-text/Markdown-source/ASCII editor,
  Markdown preview, HTML preview, JSON viewer).
- Each line is drawn as a proportional bar; headings/code/quotes/lists are visually distinct.
- A viewport rectangle tracks the visible region; **clicking** jumps the document there and
  **dragging** the rectangle scrolls continuously.
- Opacity is adjustable in Settings ▸ Appearance and persists across launches; default is
  semi-transparent (~0.55).
- Toggling, switching theme, and switching documents never crash or leak (verified by
  build + manual smoke test in each panel).

## Design decisions (confirmed with user)
- **Scope:** all four panels in v1.
- **Render style:** abstract line blocks (no glyph rendering).
- **Interaction:** click-to-jump **and** drag-the-viewport.
- **Placement:** trailing edge of the active panel; semi-transparent; opacity in Settings.

## Architecture grounding (from guides + source)
- Editor (3.1), Markdown preview (4), JSON viewer (8) are all **`NSScrollView` + `NSTextView`**;
  only HTML preview (8) is a **`WKWebView`**. ⇒ one reusable AppKit text-minimap binder serves
  three panels; a JS-driven binder serves HTML.
- The shared primitive belongs in **Foundation 2.4 (UI/UX)** per SR-1 ("if two modules could
  share it, it belongs in Foundation"). Each panel mounts a thin overlay; no panel reaches
  into another.
- Reuse existing infra: the `WindowState.editorScrollFraction` + `boundsDidChangeNotification`
  pattern (ISS-063) for viewport tracking; `HTMLPreviewCoordinator.syncScrollToFraction`
  (`evaluateJavaScript window.scrollTo`) for the HTML path.
- Honour bridge-ownership rules (ISS-093/096): binders register observers **once**, remove them
  on teardown, hold **weak** refs, and never read SwiftUI's private `enclosingScrollView`.

## Steps

1. **Per-window visibility state**
   What: Add `var minimapVisible: Bool = false` to `WindowState`; add a delegating
   `minimapVisible` computed property + `toggleMinimap()` to `AppState` (mirroring
   `scratchpadVisible`). Transient — not added to `WindowDescriptor` (matches scratchpad).
   Why: The toggle acts on the active window; mirroring the established scratchpad pattern keeps
   state ownership consistent (SR-1) and avoids a persistence contract change in v1.

2. **Global opacity setting**
   What: Add `minimapOpacity: Double = 0.55` to `SettingsStore`, `setMinimapOpacity(_:)`
   (clamped 0.15…1.0), a `DefaultsKey.minimapOpacity`, and a load line in `loadFromDefaults`.
   Why: Opacity is an app-wide appearance preference, so it belongs in the single
   `SettingsStore` source of truth and must persist via `PersistenceService`.

3. **View-menu toggle**
   What: In `ViewMenuGroup`, add a `Toggle("Minimap", isOn:)` bound to `appState.minimapVisible`
   with `.keyboardShortcut("5", modifiers: [.control, .command])`, placed after Restore Default
   Layout (matching the mockup; ⌃⌘5 is currently unused).
   Why: Gives the user the specified entry point and shortcut without colliding with existing
   bindings (⌥⌘1–4, ⌘⇧K, ⌃⌘E/R/T/F/0).

4. **Minimap model + builder (2.4)**
   What: New `MinimapModel.swift` in 2.4 — `MinimapLine { lengthFraction: Double; kind: LineKind }`,
   `enum LineKind { plain, blank, heading, code, quote, list }` (all `Sendable`), and a
   `MinimapModelBuilder` that splits text into lines, normalizes bar length, and classifies each
   line. Pure value types, no UIKit/AppKit.
   Why: A `Sendable` model lets the (potentially large) parse run off the main actor (SR-4) and
   keeps per-line storage tiny — one `Double` + one enum, no bitmap (SR-3).

5. **Minimap drawing + interaction view (2.4)**
   What: New `MinimapView.swift` — an `NSView` that draws the bars (length ∝ `lengthFraction`,
   colour by `LineKind` via new `SputnikColor` tokens), draws the viewport rectangle, and handles
   `mouseDown`/`mouseDragged`, reporting a target scroll fraction (0…1) through a callback. Content-
   and target-agnostic.
   Why: Isolating pure drawing + hit-testing from the per-panel binding (SR-6) makes the component
   reusable across all four panels and unit-reasoned in isolation.

6. **Theme-aware colour tokens (2.4)**
   What: Add minimap bar colours per `LineKind` and a viewport-indicator tint to `SputnikColor`
   (+ any spacing constants in `DesignTokens`). Distinguish kinds by hue/brightness that read in
   both light and dark mode.
   Why: SR-1 keeps colour tokens defined once in Foundation; theme-awareness matches the existing
   design-token system.

7. **Text-panel binder (2.4)**
   What: New `MinimapScrollBinder.swift` — an `NSViewRepresentable` (or `NSView` host) that takes a
   **weak** target `NSScrollView`, observes its `NSText.didChangeNotification` (throttled, off-main
   rebuild via `Task(.utility)`) and `boundsDidChangeNotification` on the clip view, rebuilds the
   `MinimapModel`, computes the viewport fraction from `contentView.bounds` vs document height, and
   on minimap interaction scrolls the target. Reads `settings.minimapOpacity`. Registers observers
   once; removes them in `dismantleNSView`.
   Why: Encapsulates the editor/Markdown/JSON wiring in one place, reusing the ISS-063 bounds-observer
   pattern and obeying the ISS-093 "remove observers on teardown, weak refs" rule (SW-2).

8. **HTML (WebView) binder (2.4)**
   What: New `MinimapWebBinder.swift` — variant that drives a **weak** `WKWebView` via injected JS:
   reads top-level block elements' heights/tags + `scrollHeight` + `scrollY` to build the model and
   viewport; on interaction calls `window.scrollTo`. Mirrors `HTMLPreviewCoordinator.syncScrollToFraction`.
   Why: The WebView has no `NSTextStorage`, so its abstract blocks must come from the DOM; reusing the
   existing app-injected-JS approach keeps it within the module's security posture (`allowsContentJavaScript = false`).

9. **SwiftUI overlay wrapper (2.4)**
   What: New `Minimap.swift` — a thin SwiftUI view each panel drops via
   `.overlay(alignment: .trailing)`, gated on `appState.minimapVisible`, selecting the text- or
   web-binder for its target and passing `settings.minimapOpacity`.
   Why: One mount call per panel keeps consumer code minimal and uniform (SR-1/SR-6).

10. **Expose content views to the overlay**
    What: Where needed, expose each panel's owned content view as a **weak** reference on its view
    model/coordinator (editor already exposes `viewModel.textView`; add equivalents for Markdown's
    `NSScrollView`, JSON's `NSScrollView`, and HTML's `WKWebView`), set in `makeNSView`.
    Why: Avoids reading SwiftUI's private `enclosingScrollView` (ISS-096); gives the binder a stable,
    bridge-owned target reference (SW-2).

11. **Mount in the text editor (3.1)**
    What: In `TextEditorPanel.swift`, add the `Minimap` overlay targeting the editor scroll view.
    Why: Delivers the primary use case (long source documents).

12. **Mount in Markdown preview (4) and JSON viewer (8)**
    What: Add the `Minimap` overlay to `MarkdownPreviewPanel`/`MarkdownRenderView` and
    `JSONViewerPanel`, targeting each panel's `NSTextView` scroll view.
    Why: Extends the same text-binder to the two other `NSTextView`-backed panels.

13. **Mount in HTML preview (8)**
    What: Add the `Minimap` overlay (web-binder) to the `HTMLPreviewView`/panel, targeting the
    `WKWebView`.
    Why: Completes the four-panel scope using the JS-driven binder.

14. **Settings UI — opacity slider**
    What: Add an opacity `Slider` row (0.15…1.0) to `AppearanceTab.swift` in the app target, bound to
    `settings.minimapOpacity` via `setMinimapOpacity(_:)`.
    Why: Fulfils "transparency set in the settings menu."

15. **Tests + verification**
    What: Add Swift Testing cases for `MinimapModelBuilder` (line classification, length
    normalization) and viewport math (scroll offset/height → indicator rect; click fraction →
    scroll target; empty-doc and content-shorter-than-viewport edge cases). Run `swift build` and a
    manual smoke test in each of the four panels.
    Why: Locks the pure logic against regressions per the Success Condition; the rest is UI verified
    manually.

## Risks and Constraints
- **Foundation blast radius (SR-1):** new 2.4 primitive is additive; no existing Foundation type
  changes shape. Keep the binder an interface consumer — Foundation exposes the primitive, panels mount it.
- **Retain cycles / leaks (SW-2, ISS-093):** binders must hold **weak** target refs and remove all
  observers in `dismantleNSView`; long-lived notification observers otherwise leak for the app lifetime.
- **Main-thread cost (SR-4):** model rebuilds run off-main at `.utility` and are throttled; only
  drawing and scroll application touch the main actor.
- **Large documents (SR-3):** per-line storage is a `Double` + enum; no snapshot bitmap. For very
  large docs, reuse the existing large-file thresholds where the panels already degrade.
- **WebView fidelity:** the HTML minimap is DOM-approximate (block heights), not pixel-exact — acceptable
  for navigation; documented at the call site.
- **No force-unwraps (SR-2)** anywhere in production paths; guard the optional target refs.
- **AppKit only where required (SW-3):** `MinimapView` is `NSView` because per-pixel drawing + mouse
  hit-testing exceed SwiftUI `Canvas` ergonomics for a draggable viewport; documented at the call site.

## Files Affected
- `2 Foundation/2.2 Global State Management/WindowState.swift` — add `minimapVisible`.
- `2 Foundation/2.2 Global State Management/AppState.swift` — delegating `minimapVisible` + `toggleMinimap()`.
- `2 Foundation/2.3 Settings/SettingsStore.swift` — `minimapOpacity`, setter, key, load.
- `2 Foundation/2.0 App Overview/ViewMenuGroup.swift` — Minimap toggle (⌃⌘5).
- `2 Foundation/2.4 UI and UX/MinimapModel.swift` — **new** model + builder.
- `2 Foundation/2.4 UI and UX/MinimapView.swift` — **new** drawing + interaction NSView.
- `2 Foundation/2.4 UI and UX/MinimapScrollBinder.swift` — **new** NSTextView binder.
- `2 Foundation/2.4 UI and UX/MinimapWebBinder.swift` — **new** WKWebView binder.
- `2 Foundation/2.4 UI and UX/Minimap.swift` — **new** SwiftUI overlay wrapper.
- `2 Foundation/2.4 UI and UX/SputnikColor.swift` (+ `DesignTokens.swift`) — minimap colour/spacing tokens.
- `3 Text Editor/3.1 Text/TextEditorPanel.swift` (+ expose scroll view) — mount overlay.
- `4 Markdown Preview/MarkdownPreviewPanel.swift` / `MarkdownRenderView.swift` / `MarkdownPreviewViewModel.swift` — expose scroll view + mount overlay.
- `8 HTML Preview/JSONViewerPanel.swift` / `JSONViewerViewModel.swift` — expose scroll view + mount overlay.
- `8 HTML Preview/HTMLPreviewView.swift` / `HTMLPreviewPanel.swift` / `HTMLPreviewCoordinator.swift` — expose web view + mount overlay (web binder).
- `App-Sputnik/AppearanceTab.swift` — opacity slider.
- Tests — `MinimapModel`/viewport math cases (Foundation test target).

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (built + smoke-tested in all four panels)
- [ ] Module Guide(s) updated (`status` + `last_updated`) for 2.2, 2.3, 2.4, 3.1, 4, 8
- [ ] Changes committed: `[2 Foundation] Add Minimap`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
