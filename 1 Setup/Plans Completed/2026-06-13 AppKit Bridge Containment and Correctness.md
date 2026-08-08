---
plan: AppKit bridge containment and correctness
module: 3 Text Editor / 4 Markdown Preview / 8 HTML Preview / 9 Resources / App Entry Point / 2 Foundation
created: 2026-06-13
status: complete
related_issues: ISS-093, ISS-094, ISS-095, ISS-096, ISS-097, ISS-098, ISS-099
---

## Purpose
Fix seven containment and correctness defects in the nine `NSViewRepresentable` bridges: two
resource leaks (observer tokens never removed), one wrong-window bug, one architectural violation
(export logic inside `updateNSView`), one fragile scroll-hierarchy coupling, one always-reload
in a help panel, and one stale coordinator parent — hardening the SwiftUI/AppKit boundary to
match the project's SW-3 and SR-6 rules.

## Success Condition
- `swift build` clean across all packages — no new warnings.
- Opening and closing 10 editor tabs shows no `NSNotification`-observer leak in Instruments
  (ISS-093).
- With two windows open, activating a preference pane window does not rename the document
  window's title (ISS-094).
- Changing the Markdown font-scale slider triggers a single layout pass with no SwiftUI
  "Modifying state during view update" purple warning (ISS-095).
- Scrolling the editor through a 200-line Markdown file does not crash due to missing
  scroll view (ISS-096).
- Opening an HTML help tab and switching app focus does not flash/reload the demo (ISS-097).
- Changing `ScratchpadTextView` binding value updates correctly in the coordinator (ISS-098).
- No throwaway `SyntaxHighlighter` is allocated per load-token change (ISS-099).

## Steps

- [x] 1. **Add `dismantleNSView` to `EditorView` and `MarkdownRenderView` (ISS-093)**
   What: In `EditorView`, add:
   ```swift
   public static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
       if let token = coordinator.scrollObserverToken {
           NotificationCenter.default.removeObserver(token)
           coordinator.scrollObserverToken = nil
       }
   }
   ```
   In `MarkdownRenderView`, add the same pattern, removing `coordinator.scrollObserverToken`
   and clearing `coordinator.observedClipView`. Both coordinator types already hold the token;
   dismantling just removes it.
   Why: Block-based `NotificationCenter` observers are never removed automatically. Without
   `dismantleNSView`, the token (and any captured views) outlives the representable and leaks
   for the app's lifetime — a violation of SW-2.

- [x] 2. **Fix `WindowProxyView` to use `nsView.window` (ISS-094)**
   What: In `WindowProxyView`, change `makeNSView` and `updateNSView` to pass the view itself
   to the coordinator:
   ```swift
   func updateNSView(_ nsView: NSView, context: Context) {
       context.coordinator.updateWindow(title: title, url: documentURL, in: nsView.window)
   }
   ```
   Update `Coordinator.updateWindow(title:url:)` to accept `in window: NSWindow?` and use
   that instead of `NSApp.keyWindow`. Keep the `NSApp.keyWindow` fallback only inside
   `makeNSView`'s `DispatchQueue.main.async` (where `nsView.window` is nil until the view
   is added to the hierarchy).
   Why: Targeting `NSApp.keyWindow` writes the title onto whichever window happens to be key
   at render time — wrong in any multi-window scenario (ISS-094).

- [x] 3. **Extract export/print logic out of `MarkdownRenderView.updateNSView` (ISS-095)**
   What: Move the `printAction`, `saveAsPDFAction`, and `saveAsMarkdownAction` closure
   bodies out of `updateNSView` and into `makeNSView` (wired once). The closures capture
   `[weak textView]` already, so they remain valid after creation. Remove the
   `@Binding var printAction`, `@Binding var saveAsPDFAction`, `@Binding var saveAsMarkdownAction`
   properties from `MarkdownRenderView` and instead expose them via the `MarkdownPreviewCoordinator`
   so the parent panel can call them directly — matching the pattern already used by
   `PDFKitView` (`viewModel.printAction`, `viewModel.navigateAction`).
   Update `MarkdownPreviewPanel` (the caller) to wire against the coordinator properties
   instead of bindings.
   Why: Binding mutations inside `updateNSView` are called on every SwiftUI update pass, risk
   "Modifying state during view update" runtime warnings, and violate SR-6 — `updateNSView`
   should sync view state, not own export workflows (ISS-095).

- [x] 4. **Extract export/print logic out of `HTMLPreviewView.updateNSView` (ISS-095)**
   What: The same pattern as step 3, applied to `HTMLPreviewView`. The `printAction`,
   `saveAsPDFAction`, and `saveAsHTMLAction` closures already reference `context.coordinator`
   and `[weak webView]` — move them into `makeNSView`. Remove the `@Binding` properties
   from `HTMLPreviewView`; expose the actions via `HTMLPreviewCoordinator` properties that
   `HTMLPreviewPanel` reads directly after `makeCoordinator`.
   Why: Same reason as step 3 — `updateNSView` runs on every AppState change; building
   NSSavePanel closures there is unnecessary work and a binding-mutation hazard (ISS-095).

- [x] 5. **Own the NSScrollView inside `MarkdownRenderView` (ISS-096)**
   What: Refactor `MarkdownRenderView` to wrap the `NSTextView` in an `NSScrollView` it
   creates itself in `makeNSView` (same approach as `EditorView`/`ScratchpadTextView`),
   and change the return type from `NSTextView` to `NSScrollView`. Update the `makeNSView`
   and `updateNSView` signatures accordingly (`NSViewRepresentable` type alias `NSViewType`
   = `NSScrollView`). Remove the `textView.enclosingScrollView` accesses that were reaching
   into SwiftUI's private scroll hierarchy; use the owned `NSScrollView` directly for
   scroll-position reads/writes and for observer registration. Remove the SwiftUI
   `ScrollView { }` wrapper in `MarkdownPreviewPanel` that was hosting this view, since
   the bridge now handles its own scrolling.
   Why: Accessing `textView.enclosingScrollView` references a SwiftUI-internal
   `NSScrollView` that is not API-contracted and has broken between macOS releases;
   owning the scroll view inside the bridge is the documented safe pattern (ISS-096).

- [x] 6. **Add a reload guard to `SandboxedHTMLDemo` and deduplicate the template (ISS-097)**
   What: Add a `lastLoadedHTML: String` property to `SandboxedHTMLDemo.Coordinator`.
   In `updateNSView`, compare the new `wrapped` string against `coordinator.lastLoadedHTML`
   and return early if equal. Assign `coordinator.lastLoadedHTML = wrapped` after calling
   `loadHTMLString`. Extract the HTML template into a `private func wrappedHTML(_ body: String) -> String`
   helper called from both `makeNSView` and `updateNSView` — eliminating the duplication
   and the existing drift in the `@media` dark-mode block.
   Why: Without the guard every AppState change reloads and reflashes the demo web view;
   the duplicated template has already drifted between the two copies (ISS-097).

- [x] 7. **Fix `ScratchpadTextView` coordinator to refresh `parent` on update (ISS-098)**
   What: In `ScratchpadTextView.updateNSView`, add:
   ```swift
   context.coordinator.parent = self
   ```
   This is the standard SwiftUI coordinator pattern for value-type representables.
   Why: The coordinator stores a copy of the struct assigned once at `makeCoordinator`
   time; if any non-binding property is ever read from `parent` after the view updates,
   it will silently read a stale value. The fix is the documented one-liner (ISS-098).

- [x] 8. **Remove the duplicate `SyntaxHighlighter` in `EditorView.updateNSView` (ISS-099)**
   What: In `EditorView.updateNSView`, replace the throwaway highlighter construction:
   ```swift
   // Before (creates a new highlighter, discards it after one use):
   let highlighter = SyntaxHighlighter(textStorage: storage)
   highlighter.codeBlockHighlightEnabled = settings.codeBlockHighlightEnabled
   highlighter.highlight(mode: viewModel.mode)
   ```
   with a call to the coordinator's existing instance:
   ```swift
   if let highlighter = context.coordinator.syntaxHighlighter {
       highlighter.codeBlockHighlightEnabled = settings.codeBlockHighlightEnabled
       highlighter.highlight(mode: viewModel.mode)
   }
   ```
   Why: A fresh `SyntaxHighlighter` is constructed and discarded on every load-token
   change — this is wasted allocation and means `codeBlockHighlightEnabled` is applied
   to the throwaway, not to the live coordinator instance used for subsequent edits (ISS-099).

- [x] 9. **Re-verify and update affected Module Guides**
   What: After all steps pass, update:
   - `1 Setup/Module Guides/3 Text Editor Window/guide.md` — note `dismantleNSView` removes
     scroll observer; `updateNSView` initial highlight uses coordinator's highlighter.
   - `1 Setup/Module Guides/4 Markdown Preview/guide.md` — note bridge owns its
     `NSScrollView`; export actions wired in `makeNSView`; `dismantleNSView` added.
   - `1 Setup/Module Guides/8 HTML Preview/guide.md` — note export actions moved to
     coordinator/`makeNSView`.
   Set `status: stable`, `last_updated: 2026-06-13`, `last_verified: 2026-06-13` on each.
   Why: Guides must reflect code reality; drifted guides cause future bugs.

## Risks and Constraints
- **Step 5 (own the scroll view):** Changing `MarkdownRenderView`'s `NSViewType` from
  `NSTextView` to `NSScrollView` is a public-type change — search for any call sites that
  downcast the representable's underlying view. The `MarkdownPreviewPanel` is the only
  known consumer.
- **Steps 3 & 4 (remove @Binding):** The parent panel views (`MarkdownPreviewPanel`,
  `HTMLPreviewPanel`) pass these bindings today; removing them requires updating both the
  bridge's init signature and the panel's call site. Do both in the same commit so the
  build stays green.
- **Step 5 (scroll restore timing):** The `asyncAfter(+0.05 s)` timing hack for scroll
  restore in `MarkdownRenderView` remains fragile (ISS-090) and is out of scope for this
  plan. It should be preserved as-is and addressed separately.
- **Foundation is not touched** — all changes are isolated to the bridge files in modules
  3, 4, 8, 9, and the app entry point.

## Files Affected
- `3 Text Editor/3.1 Text/EditorView.swift` — add `dismantleNSView`; use coordinator's highlighter
- `4 Markdown Preview/MarkdownRenderView.swift` — add `dismantleNSView`; own `NSScrollView`; move export closures to `makeNSView`; remove `@Binding` export properties
- `4 Markdown Preview/MarkdownPreviewPanel.swift` — update call site to remove binding args; read actions from coordinator
- `8 HTML Preview/HTMLPreviewView.swift` — move export closures to `makeNSView`; remove `@Binding` export properties
- `8 HTML Preview/HTMLPreviewCoordinator.swift` — expose action properties; coordinator set in `makeNSView`
- `8 HTML Preview/HTMLPreviewPanel.swift` — update call site to remove binding args (if applicable)
- `App-Sputnik/WindowProxyView.swift` — use `nsView.window` instead of `NSApp.keyWindow`
- `9 Resources/Sources/9.4 Html Help/HTMLHelpPanelView.swift` — add reload guard; deduplicate template
- `2 Foundation/2.4 UI and UX/ScratchpadTextView.swift` — refresh `parent` in `updateNSView`
- `1 Setup/Module Guides/3 Text Editor Window/guide.md` — update
- `1 Setup/Module Guides/4 Markdown Preview/guide.md` — update
- `1 Setup/Module Guides/8 HTML Preview/guide.md` — update

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[3+4+8+9] AppKit bridge containment and correctness`
- [ ] Pushed to GitHub
- [x] Plan moved to Plans Completed/
