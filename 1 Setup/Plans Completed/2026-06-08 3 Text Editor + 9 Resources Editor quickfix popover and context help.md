---
plan: Editor click-to-fix popover + right-click contextual help panel
module: 3 Text Editor (3.5 / 3.1) + 9 Resources + 2 Foundation (2.2 / 2.4)
created: 2026-06-08
status: pending
related_issues: ISS-008 (logged this plan); ISS-004 (existing — settings seam)
---

## Purpose
Give the plain-text editor a single-click quick-fix popover for both spelling and grammar issues (spelling prioritised over grammar), and a right-click "Look Up Help" action on any selection that opens the help panel matching the active editor mode (Grammar, HTML, Markdown, or ASCII Art) to the most relevant topic.

## Success Condition
1. Open a `.txt` file containing a misspelling and a grammar mistake. Spelling underlines **red**, grammar underlines **orange**.
2. Where a spelling and grammar issue overlap the same word, only the **red** spelling underline shows. **Single-click** the underline → a popover appears with the suggested correction (**Fix**) and a **Dismiss** button.
3. Click **Fix** → the word is replaced. Click **Dismiss** → the underline clears and, if a grammar issue was hidden beneath a dismissed spelling word, the **orange** grammar underline now appears.
4. Select a word/phrase/sentence and **right-click** → a "Look Up in … Help" item appears for the active mode (Grammar in plain text; HTML / Markdown / ASCII Art when that mode is active and present). Choosing it reveals the matching help panel scrolled to the relevant topic.

## Steps

- [ ] 1. **Recolour grammar underline green → orange**
   What: In `SpellingGrammarChecker.swift` change the `.grammar` branch `underlineColor` from `NSColor.systemGreen` to `NSColor.systemOrange`. Update the 3.5 guide diagram/summary ("green underline" → "orange underline").
   Why: User-chosen colour; keeps spelling (red) and grammar (orange) visually distinct.

- [ ] 2. **Introduce an annotation model the editor can hit-test**
   What: Add a small `Sendable` value type (e.g. `GrammarAnnotation { range: NSRange; kind: .spelling/.grammar; suggestions: [String] }`) and have `SpellingGrammarChecker` keep the current annotations in an array alongside writing underline attributes. One responsibility per file (SR-6) — put the type in its own file under 3.5.
   Why: A click needs to map a character location back to the issue and its suggestions; today only opaque underline attributes exist, with no queryable model.

- [ ] 3. **Apply spelling-over-grammar priority at render time**
   What: When writing underlines, if a `.grammar` result's range overlaps any `.spelling` range, do not draw the grammar underline and mark that grammar annotation as *suppressed* (kept in the model, not rendered).
   Why: User requirement — spelling takes precedence; the grammar issue should only surface once the overlapping spelling issue is resolved.

- [ ] 4. **Add a dismissed/ignored set per document**
   What: Track dismissed items: for spelling use `NSSpellChecker.ignoreWord(_:inSpellDocumentWithTag:)`; for grammar keep a per-document ignored-range/phrase set in the checker. Re-running the check must exclude ignored items.
   Why: Dismiss must be durable for the session and must not re-underline on the next debounce pass.

- [ ] 5. **Re-run the check after a dismiss so suppressed grammar surfaces**
   What: After a dismiss, call the existing check pass; because the dismissed spelling word is now ignored, its range no longer suppresses the overlapping grammar annotation, which then renders orange.
   Why: Delivers the "dismiss spelling → underlying grammar appears" behaviour from the Success Condition (a Fix already triggers this via the text-change debounce).

- [ ] 6. **Build the click-to-fix popover**
   What: Add a SwiftUI view (`QuickfixPopover`) showing the top suggestion(s) with a **Fix** button and a **Dismiss** button, hosted via `NSPopover` anchored to the clicked range's bounding rect. New file under 3.5 (SR-6). SwiftUI-first (SW-3); the `NSPopover` host is the AppKit seam, documented at the call site.
   Why: User chose a single-click popover (not a right-click list) as the primary interaction, for both spelling and grammar.

- [ ] 7. **Hit-test single clicks in the editor and present the popover**
   What: In `EditorTextView`, on a single left click (no drag, no selection), convert the click point to a character index and look it up in the annotation model; if it lands on a rendered underline, present the popover anchored there. Otherwise fall through to normal `NSTextView` behaviour.
   Why: Wires the popover to the gesture without disturbing caret placement, selection, or ghost-text handling already in `EditorTextView.keyDown`.

- [ ] 8. **Wire popover Fix / Dismiss actions**
   What: Fix → `NSTextStorage.replaceCharacters(in:with:)` with the chosen suggestion (guard stale ranges, as the existing `QuickfixPresenter` does). Dismiss → add to the ignored set (step 4) and re-run the check (step 5). All on `@MainActor`.
   Why: Completes the popover loop; mirrors the existing correction-application safety (range-validity guard).

- [ ] 9. **[FOUNDATION] Let help routing carry a target topic ID (resolves ISS-008)**
   What: Extend Foundation's help-request state so it can carry an optional topic ID, not just a `HelpTopic` kind — e.g. add `AppState.requestedHelpTarget: HelpRequest?` where `HelpRequest { kind: HelpTopic; topicID: String? }` (keep `requestedHelpTopic` working, or fold it in). Module 9 panels observe this and navigate to `topicID` when present.
   Why: SR-1 — gives every panel one shared, Foundation-owned route to "reveal + navigate to topic", instead of the editor reaching into four bespoke coordinator mechanisms (notification / closure / async). **Foundation change — affects all help panels; flagged explicitly per !GenerateAPlan rules.**

- [ ] 10. **Have each help panel honour the target topic ID**
   What: In the four panel views (`GrammarHelpPanelView`, `HTMLHelpPanelView`, `MarkdownHelpPanelView`, `ASCIIArtHelpPanelView`), observe the Foundation help-target and, when revealed with a `topicID`, navigate to that topic. Reuse each coordinator's existing `openHelp(for:)`/lookup internals behind this single observation point.
   Why: Converges the four mechanisms onto the Foundation route from step 9 without rewriting the coordinators' matching logic.

- [ ] 11. **Add the editor right-click "Look Up Help" menu item**
   What: Override `menu(for:)` in `EditorTextView` to append a context item when there is a selection. Pick the target by `EditorViewModel.mode` / gating flags: `.plainText` → Grammar Help; `.markdown` → Markdown Help; `.html` (and/or `htmlModeActive`) → HTML Help; `.asciiArt` → ASCII Art Help. Only show the item when that mode is active/present.
   Why: User requirement — selection + right-click opens the relevant panel, gated to the modes that are "turned on and present".

- [ ] 12. **Resolve the selection to a topic and route to the panel**
   What: On selection, call the matching coordinator's resolver (`GrammarHelpCoordinator.lookup`, `HTML/Markdown lookupContext`, `ASCIIArtHelpCoordinator.bestMatch`) with the selected text (and cursor offset where required); take the resulting topic ID and set the Foundation help-target (step 9) with the right `kind` + `topicID`. If nothing matches, reveal the panel at its default/overview topic.
   Why: Turns an arbitrary word/phrase/sentence selection into a concrete panel + topic, reusing each module's existing matching logic (SR-1: editor asks the coordinator, doesn't reimplement matching).

- [ ] 13. **Update Module Guides**
   What: Update the 3.5 guide (orange grammar underline; spelling+grammar click popover; spelling-over-grammar priority; dismiss/ignore). Add the right-click help-lookup flow to the relevant 9.x guide(s), and note the Foundation help-target in the 2.2/2.4 guides. Stamp `last_updated: 2026-06-08`.
   Why: The guide is the source of truth (Working Conventions); these features change documented behaviour.

## Risks and Constraints
- **Foundation change (step 9)** touches shared help-routing state consumed by all four panels — keep it a Foundation-owned primitive/protocol, not orchestration logic (SR-1). Verify each panel still opens correctly from the existing Help menu after the change.
- **SW-3 boundary:** the popover/host and click hit-testing live in AppKit (`EditorTextView`, `NSPopover`) by necessity; document the reason at each call site. Keep presentation/layout in SwiftUI.
- **SW-2 retain cycles:** the popover, click handler, and any new observers must use `[weak self]`; `EditorTextView` already holds its collaborators `weak`.
- **SR-2 / stale ranges:** every range mutation must guard `NSNotFound` and `location + length <= storage.length` (matching existing `QuickfixPresenter`/checker guards) — edits during the debounce window can invalidate ranges.
- **Spelling/grammar priority ordering** must survive re-runs: a Fix changes text (auto re-check) while a Dismiss does not (explicit re-check) — both paths must converge on the same suppressed-grammar-now-visible result.
- **ISS-004 (open):** the spell-check debounce/locale already sit as local defaults pending Foundation 2.3; do not deepen that seam — reuse the existing `settings.spellCheckDebounceInterval` / `settings.spellCheckLocale` accessors.
- **Performance (SR-4):** click hit-testing reads the in-memory annotation model only — no re-scan on click; re-checks stay on the existing debounced background pass.

## Files Affected
- `3 Text Editor/3.5 Spelling and Grammar Checking/SpellingGrammarChecker.swift` — orange grammar colour; maintain annotation model; spelling-over-grammar suppression; ignored set; re-run-after-dismiss.
- `3 Text Editor/3.5 Spelling and Grammar Checking/GrammarAnnotation.swift` — **new**; the hit-testable annotation value type.
- `3 Text Editor/3.5 Spelling and Grammar Checking/QuickfixPopover.swift` — **new**; SwiftUI Fix/Dismiss popover.
- `3 Text Editor/3.5 Spelling and Grammar Checking/QuickfixPresenter.swift` — extend to grammar suggestions / share suggestion lookup with the popover (or fold into popover path).
- `3 Text Editor/3.1 Text/EditorTextView.swift` — single-click hit-test + popover presentation; `menu(for:)` override for the help-lookup item.
- `2 Foundation/2.2 Global State Management/AppState.swift` — help-target state carrying optional topic ID (ISS-008).
- `2 Foundation/2.4 UI and UX/HelpTopic.swift` — `HelpRequest` (kind + topicID) primitive, if added here.
- `9 Resources/9.5 Grammar Help/GrammarHelpPanelView.swift`, `9.4 Html Help/HTMLHelpPanelView.swift`, `9.3 Markdown Help/MarkdownHelpPanelView.swift`, `9.2 ASCII art Help/ASCIIArtHelpPanelView.swift` — observe the Foundation help-target and navigate to `topicID`.
- `1 Setup/Module Guides/3 Text Editor Window/3.5 Spelling and Grammar Check/guide.md` (+ relevant 9.x and 2.2/2.4 guides) — doc updates.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[3 Text Editor + 9 Resources] Editor click-to-fix popover + contextual help`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
