---
plan: Print and PDF format toggle (plain text vs rendered)
module: 3 Text Editor, 4 Markdown Preview, 8 HTML Preview, 2 Foundation
created: 2026-06-13
status: in-progress
related_issues: none
---

## Purpose
When a Markdown or HTML preview panel is open and paired with the active editor document, "Print…" and "Save as PDF…" should ask whether the user wants plain-text or rendered output, instead of silently using only plain text.

## Success Condition
1. Open a `.md` file. The Markdown preview panel renders it.
2. Click the editor's `…` overflow menu → "Save as PDF…" — a two-button alert appears: **Plain Text** and **Rendered**.
   - Choosing **Plain Text** saves the raw source as a PDF (existing behaviour).
   - Choosing **Rendered** saves the styled Markdown preview as a PDF.
3. File menu → "Print…" — same two-button alert appears and both paths work.
4. Open a `.html` file. The HTML preview panel renders it. Steps 2 and 3 repeat, with "Rendered" producing a PDF/printout of the live HTML preview.
5. Open a `.txt` file (no preview panel active). No alert appears — "Save as PDF…" and "Print…" go directly to the plain-text path as before.

## Steps

- [x] 1. **Add `pairedPreviewPrintAction` and `pairedPreviewSaveAsPDFAction` to `AppState`**
   What: Add two `@MainActor var pairedPreviewPrintAction: (() -> Void)?` and `pairedPreviewSaveAsPDFAction: (() -> Void)?` fields to `AppState` (2.2). No persistence needed — these are live capability signals only.
   Why: SR-1 requires cross-module coordination to go through Foundation. This is the established pattern (`editorCommandHandler` on AppState uses the same shape). Without a Foundation bridge the editor and file menu cannot discover whether a preview panel is active.

- [x] 2. **Markdown Preview Panel: write closures into AppState when paired**
   What: In `MarkdownPreviewPanel`, extend the existing `.task { ... }` / `.onChange` block that handles `saveAsPDFAction` wiring. After the existing `MarkdownRenderView` makes closures available, also assign them to `appState.pairedPreviewPrintAction` and `appState.pairedPreviewSaveAsPDFAction`. Clear both fields (set to `nil`) in the same block when the active document is not `.markdown`/`.ascii` or when there is no active document. Also clear in `.onDisappear`.
   Why: AppState must always reflect the current state — stale closures from a previous document would offer "Rendered" when no preview is actually paired.

- [x] 3. **HTML Preview Panel: write closures into AppState when paired**
   What: Same pattern as step 2. In `HTMLPreviewPanel`, when the active document is `.html`, assign `appState.pairedPreviewPrintAction` (pointing at the coordinator's print action) and `appState.pairedPreviewSaveAsPDFAction` (pointing at the coordinator's save-as-PDF action) to `AppState`. Clear in the not-`.html` / no-doc branches and in `.onDisappear`.
   Why: Same Foundation contract — the HTML preview must register and deregister its capabilities as it activates and deactivates.

- [x] 4. **TextEditorPanel overflow menu: show format choice alert for "Save as PDF…"**
   What: In `TextEditorPanel`, update the "Save as PDF…" button action. If `appState.pairedPreviewSaveAsPDFAction` is non-nil, present an `NSAlert` with message "Save as PDF" and two buttons: **Plain Text** and **Rendered**. Route to the existing `saveAsPDFAction` or `appState.pairedPreviewSaveAsPDFAction` based on the user's choice. If the field is `nil`, proceed directly (no alert — existing behaviour).
   Why: The editor is the most natural discovery point for this choice, and the alert avoids introducing a new UI element.

- [x] 5. **FileMenuGroup: show format choice alert for "Print…"**
   What: In `FileMenuGroup`, update the "Print…" button action. Apply the same conditional-alert logic as step 4: if `appState.pairedPreviewPrintAction` is non-nil, show an `NSAlert` with **Plain Text** / **Rendered** buttons. **Plain Text** → `NSApp.sendAction(#selector(NSDocument.printDocument(_:)), to: nil, from: nil)` (existing path). **Rendered** → `appState.pairedPreviewPrintAction?()`.
   Why: Print is menu-bar-driven and the file menu is the expected home; must match the editor-panel behaviour.

- [ ] 6. **Verify closure lifecycle — no stale actions after document switch**
   What: Manually test: open a `.md` file → switch to a `.txt` file → trigger "Save as PDF…" and "Print…" and confirm no alert appears. Then switch back to the `.md` file and confirm the alert reappears.
   Why: The `.onChange` clear paths in steps 2–3 could race with the new document's render cycle; this test catches that before shipping.

## Risks and Constraints
- **SR-1:** Preview panels must set and clear `AppState` fields only — they must not call editor methods directly and must not import module 3.
- **SW-2:** The closures stored on AppState will capture `[weak textView]` / `[weak webView]` — verify these captures are already weak in the source panel before wiring through AppState. Both panels already use `[weak textView]` in their PDF closures, so this is safe.
- **Ordering — HTML preview:** `HTMLPreviewPanel` wires its print/PDF actions through the `Coordinator` (not directly on the view). The closures should be extracted from the coordinator at the same point the panel currently exposes them via `$saveAsPDFAction`.
- **`.onDisappear` race:** If the panel is closed while an NSSavePanel sheet is in progress, the closure referencing the (now-deallocated) WKWebView/NSTextView must not crash. The existing `[weak textView]`/`[weak webView]` guards already handle this — no extra work needed.
- **No new UI control needed:** The two-button NSAlert is sufficient. No toolbar toggle, no Settings entry.

## Files Affected
- `2 Foundation/2.2 Global State Management/AppState.swift` — add `pairedPreviewPrintAction` and `pairedPreviewSaveAsPDFAction` fields
- `4 Markdown Preview/MarkdownPreviewPanel.swift` — write/clear both closures in existing wiring block and `.onDisappear`
- `8 HTML Preview/HTMLPreviewPanel.swift` — write/clear both closures in existing wiring block and `.onDisappear`
- `3 Text Editor/3.1 Text/TextEditorPanel.swift` — conditional-alert logic in "Save as PDF…" button action
- `2 Foundation/2.0 App Overview/FileMenuGroup.swift` — conditional-alert logic in "Print…" button action

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[3+4+8] Print and PDF format toggle`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
