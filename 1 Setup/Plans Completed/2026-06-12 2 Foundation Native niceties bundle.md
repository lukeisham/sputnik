---
plan: Native niceties bundle
module: 2 Foundation (2.6 App Lifecycle) + 6 Project File Tree
created: 2026-06-12
status: completed
related_issues: none
---

## Purpose
Add the smaller standard macOS affordances that, together, make Sputnik feel like a first-class document app: title-bar proxy icon, native window tabbing, Quick Look in the File Tree, light haptic feedback, and a verified Sudden Termination / autosave posture.

## Success Condition
- A window editing a file shows the document's **proxy icon** in the title bar; ⌘-clicking the title reveals the path; dragging the proxy icon works.
- **Window → Merge All Windows / native tabbing** works (windows can be tabbed).
- Pressing **space** on a selected file in the File Tree shows a **Quick Look** preview.
- Snap/align interactions (e.g. column drag settling) emit a subtle **haptic** on supported trackpads.
- Quitting with no unsaved work does not block; autosave/Sudden Termination behaviour is documented and correct.

## Steps

- [x] 1. **Set the window's represented file (proxy icon)**
   What: When a window's active document is a file URL, set the underlying `NSWindow.representedURL` (and `title`); clear it for untitled buffers.
   Why: The proxy icon + ⌘-click path menu is a defining document-app behaviour and is currently absent.

- [x] 2. **Enable native window tabbing**
   What: Confirm/enable `NSWindow.tabbingMode`/allowsAutomaticWindowTabbing for the main `WindowGroup` so "Merge All Windows" and tab bars work.
   Why: Users expect to tab document windows; SwiftUI `WindowGroup` supports it but the behaviour should be explicit and verified.

- [x] 3. **Add Quick Look to the File Tree**
   What: Wire spacebar on a selected File Tree row to present `QLPreviewPanel` for that file URL (read-only preview), dismissing on space/escape.
   Why: Spacebar Quick Look is a universal Finder-trained gesture; its absence is immediately noticeable.

- [x] 4. **Add subtle haptic feedback on snap interactions**
   What: Call `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime:)` at column drop/snap settle points in the panel drag code.
   Why: Alignment haptics make drag-to-arrange feel physical and native on supported hardware; no-op elsewhere.

- [x] 5. **Audit Sudden Termination / autosave posture**
   What: Review the `applicationShouldTerminate` gate (PTY cleanup) and layout flush; confirm a clean state allows prompt quit and that there is no data-loss window between edit and flush.
   Why: SR-2 — termination must never lose work or hang; this verifies the existing gate behaves correctly alongside the new proxy/tab state.

- [ ] 6. **Verify each affordance**
   What: Manually confirm proxy icon + ⌘-click path, window merge/tab, spacebar Quick Look, haptic on a trackpad, and a clean quick quit.
   Why: This plan is a bundle of independent small wins — each must be checked individually against the Success Condition.

## Risks and Constraints
- SW-3: setting `representedURL`/tabbing/haptics requires reaching the `NSWindow` from SwiftUI — use a minimal, documented representable/`NSApp` bridge, not a broad AppKit takeover.
- SR-1: window-level concerns live in 2.6 App Lifecycle; Quick Look is File-Tree-specific and stays in module 6.
- SR-2: the Quick Look panel and proxy-icon code must handle missing/deleted files without force-unwrapping the URL.
- Haptics must degrade silently on hardware without a haptic trackpad (the API already no-ops — verify).
- Touch the termination gate carefully: it currently guards PTY cleanup (module 7) — do not weaken it.

## Files Affected
- `2 Foundation/2.6 App Lifecycle/SputnikApp.swift` / `ContentView.swift` — `representedURL`, tabbing, window bridge
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — Sudden Termination / autosave audit (likely no change)
- `2 Foundation/2.4 UI and UX/PanelColumnView.swift` / drag code — alignment haptic at snap points
- `6 Project File Tree/` — spacebar Quick Look via `QLPreviewPanel`

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (proxy icon, tabbing, Quick Look, haptic, clean quit) — *manual step*
- [ ] Module Guide(s) updated — *no guides exist yet for modules 2 or 6*
- [x] Changes committed: `[2 Foundation] Native niceties bundle`
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
