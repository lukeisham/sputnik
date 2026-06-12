---
plan: Apple Intelligence Writing Tools and On-Device AI
module: 3 Text Editor (3.1 Text), 2 Foundation (2.2 Global State, 2.7 Utilities)
created: 2026-06-12
status: pending
related_issues: none
---

## Purpose
Enable Apple Intelligence Writing Tools in Sputnik's text editor, register NSUserActivity for Spotlight/Siri context, and add on-device text summarization via the NaturalLanguage framework — all with `#available(macOS 15.0, *)` guards so the app continues to work on macOS 14.

## Success Condition
1. The text editor responds to Apple Intelligence Writing Tools (Proofread, Rewrite, Summarize) on macOS 15+
2. Sputnik's open documents appear in Spotlight and Siri suggestions via NSUserActivity
3. Right-clicking a selection shows "Summarize Locally" which produces an on-device summary using NLSummarizer
4. All three features degrade gracefully on macOS 14

## Steps

- [ ] 1. **Add `writingToolsBehavior = .complete` to EditorTextView**
   What: In `EditorTextView.swift`, add a setup call inside `configureTypography` (or a new `configureAppleIntelligence` method) that sets `writingToolsBehavior = .complete` when running on macOS 15+.
   Why: Without this explicit opt-in, Apple Intelligence may only offer a subset of Writing Tools (e.g. no Rewrite or Summarize). This single line unlocks Proofread, Rewrite, and Summarize in the text editor.

- [ ] 2. **Register NSUserActivity on document open**
   What: In `EditorViewModel`, when a file is loaded (in `resetForNewFile` or the file-open path), create an `NSUserActivity` with activity type `"com.lukeisham.sputnik.editing"`, set its `title` to the filename, populate `userInfo` with mode and file URL, mark it eligible for prediction and search, and call `becomeCurrent()`.
   Why: Apple Intelligence uses `NSUserActivity` to understand context. This enables Spotlight indexing of open documents, Siri Suggestions for recently edited files, and contextual awareness for Writing Tools.

- [ ] 3. **Clear NSUserActivity on document close**
   What: In `EditorViewModel`, when a document is closed, call `userActivity?.resignCurrent()` and nil it out.
   Why: Prevents stale activity entries — a closed document should no longer appear in Siri Suggestions or Spotlight.

- [ ] 4. **Add "Summarize Locally" to the right-click menu**
   What: In `EditorTextView.menu(for:)`, after the existing More Context items, add a menu item "Summarize Locally" (gated on `#available(macOS 15.0, *)`). When selected, call `NLSummarizer.summarize(_:)` on the selected text, then present the result in an `NSPopover` with a SwiftUI view (similar to `QuickfixPopover`).
   Why: Provides a zero-latency, fully on-device summarization feature using Apple's built-in models — no API key, no network, no third-party dependency.

- [ ] 5. **Update module guide for 3.1 Text**
   What: Add entries for `NSUserActivity` handling and `writingToolsBehavior` to the Technical Summary and Source Files sections of `1 Setup/Module Guides/3 Text Editor Window/3.1 Text/guide.md`. Set `last_updated` to today.
   Why: The module guide is the source of truth — it must reflect the new capabilities.

## Risks and Constraints
- All Apple Intelligence APIs (`writingToolsBehavior`, `NLSummarizer`) are macOS 15+ only — every call site must use `#available(macOS 15.0, *)` guards. The app's deployment target is macOS 14.
- `NLSummarizer` is a relatively new API introduced in macOS 15 — verify exact API spelling and availability before use.
- `NSUserActivity.becomeCurrent()` should only be called on the main actor — `EditorViewModel` is already `@MainActor`, so this is safe.
- Existing `menu(for:)` in `EditorTextView` (line 158) appends items at index 0 (reversed). The new item must be inserted consistently with that pattern.

## Files Affected
- `3 Text Editor/3.1 Text/EditorTextView.swift` — add `writingToolsBehavior = .complete` on macOS 15+
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — create/resign `NSUserActivity` on document open/close
- `3 Text Editor/3.1 Text/EditorTextView.swift` — add "Summarize Locally" menu item and popover handler
- May need a small SwiftUI popover view for the summary result (or reuse `QuickfixPopover` pattern)
- `1 Setup/Module Guides/3 Text Editor Window/3.1 Text/guide.md` — update Technical Summary and Source Files

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (build succeeds; Writing Tools appear on macOS 15; right-click shows Summarize; macOS 14 builds without errors)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[3 Text Editor] Apple Intelligence Writing Tools and On-Device AI`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
