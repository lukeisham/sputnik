---
plan: Inline predictive autocomplete + granular assist settings
module: 3 Text Editor (3.1–3.5) + 2 Foundation (2.3 Settings, 2.4 UI/UX, 2.7 Utilities) + 9 Resources (9.1–9.5)
created: 2026-06-09
status: pending
related_issues: ISS-004 (open, partially advanced), ISS-011 (open, this plan resolves by design); coordinates with pending plans "More Context shared lookup utility" and "Unify Help Navigation Route"
---

## Purpose
Add inline predictive **Auto-Complete** to the editor — drawing word/phrase candidates from a parallel completion corpus derived from the 9 Resources help data (and from the built-in macOS dictionary for spelling) — and expose a **per-language × per-function** writing-assist toggle matrix (Spelling · Grammar · Markdown · HTML · ASCII × Instant Correct · Auto-Complete · More Context) that lets each function be switched on or off independently, all owned once in Foundation.

## Success Condition
- Typing a word prefix in the editor shows a greyed ghost-text completion drawn from the relevant 9 Resources corpus (Grammar/Markdown/HTML/ASCII) or the macOS dictionary (Spelling); Tab accepts, any other key dismisses — reusing the existing `GhostTextOverlay`, not a new overlay.
- The Edit menu exposes a **Writing Assistance** submenu with the per-language × per-function toggles; toggling a cell off immediately stops that behaviour for that language, and the state persists across launches.
- `SettingsStore.spellCheckEnabled` / `grammarCheckEnabled` continue to work for existing consumers but are now computed over the matrix (single source of truth — ISS-011 closed).
- The existing **manual quickfix popover and dismiss path are unchanged**: clicking an underline still opens `QuickfixPopover` with its suggestions; `onFix` applies the correction and `onDismiss` ignores+rechecks; `QuickfixPresenter` right-click corrections and `SpellingGrammarChecker.dismiss(_:)` all behave exactly as before. Instant Correct only adds an automatic invocation of the same path.
- Foundation imports no module-9 type; the concrete completion corpus lives in module 9 and is reached through a Foundation 2.7 protocol (mirrors the More Context plan's resolver pattern, SR-1).
- No force-unwraps; `[weak self]` in every escaping closure; builds clean under Swift 6 strict concurrency; corpus is loaded lazily and held as a compact prefix index (SR-3).

## Architectural decisions
- **SR-1 seam (consistent with the More Context plan).** Foundation 2.7 owns a content-agnostic `CompletionProviding` protocol + `CompletionQuery`/`CompletionResult` value types. Module 9 owns the one concrete `SputnikCompletionCorpus` that knows the help indices. Editor providers depend on the protocol, never on module 9.
- **Corpus is parallel, not the help body (option 3).** The help `body` text stays the source for *More Context*. A separate, curated completion dataset (`completions.json` per relevant 9.x submodule) is derived from each topic's `title` + `searchTerms` (+ selected body tokens) and hand-tuned. Generating it is a build step, not a runtime parse of prose (SR-3, SR-4).
- **Matrix is the single settings source (ISS-011).** A new `WritingAssistMatrix` (Codable, Sendable) holds the cells; `spellCheckEnabled`/`grammarCheckEnabled` become computed wrappers over the Spelling/Grammar × Instant-Correct cells so no consumer breaks.
- **Confirmed applicability matrix.** Each function applies only to the languages below; non-applicable cells do **not** exist in `WritingAssistMatrix` and are **not** shown in the menu (no reserved no-ops):

  | Language | Instant Correct | Auto-Complete | More Context |
  |---|:---:|:---:|:---:|
  | **Spelling** | ✓ | ✓ (macOS dictionary) | — |
  | **Grammar** | ✓ | — | ✓ |
  | **Markdown** | — | ✓ (corpus) | ✓ |
  | **HTML** | — | ✓ (corpus) | ✓ |
  | **ASCII** | — | ✓ (corpus) | — |

  - **Instant Correct → Spelling + Grammar only** (auto-apply the top correction on the existing `SpellingGrammarChecker`/quickfix path).
  - **Auto-Complete → Spelling, Markdown, HTML, ASCII** — **not Grammar**. Spelling draws from the macOS dictionary; Markdown/HTML/ASCII from the 9 Resources corpus. Grammar's 9 Resources data is used **only** for More Context, never for completion, so no Grammar completion corpus is built.
  - **More Context → Grammar, Markdown, HTML only** — Spelling has no help panel and ASCII's more-context is editor-local; these cells gate the gesture built by the separate pending plans.

## Steps

1. **Foundation 2.3 — define the assist matrix type**
   What: Add `2 Foundation/2.3 Settings/WritingAssistMatrix.swift` — `WritingAssistFunction` enum (`.instantCorrect`, `.autoComplete`, `.moreContext`), `WritingAssistLanguage` enum (`.spelling`, `.grammar`, `.markdown`, `.html`, `.asciiArt`), and a `WritingAssistMatrix: Codable, Sendable` storing one `Bool` per applicable cell with `isEnabled(_:for:)` / `setting(_:for:_:)` accessors and an `applies(_:to:)` static map encoding the confirmed applicability — Instant Correct: `{.spelling, .grammar}`; Auto-Complete: `{.spelling, .markdown, .html, .asciiArt}` (not `.grammar`); More Context: `{.grammar, .markdown, .html}`. Non-applicable cells are not stored and `isEnabled` returns `false` for them.
   Why: One typed value object for the whole matrix keeps `SettingsStore` clean and gives the menu + providers a single contract (SR-6, SR-1).

2. **Foundation 2.3 — store the matrix in `SettingsStore` and fold the legacy bools into it**
   What: Add `writingAssist: WritingAssistMatrix` (persisted as one Codable setting via `PersistenceService`, new `DefaultsKey`) with a `setWritingAssist(_:for:_:)` mutator. Convert `spellCheckEnabled`/`grammarCheckEnabled` from stored properties to computed properties backed by `writingAssist` (`spelling/grammar × .instantCorrect`); keep `setSpellCheckEnabled`/`setGrammarCheckEnabled` as thin wrappers that write the matrix. Migrate the two legacy `DefaultsKey`s on first load.
   Why: Single source of truth (ISS-011); existing consumers (`SputnikCommands`, `SpellingGrammarChecker`) keep compiling unchanged.

3. **Foundation 2.7 — define the completion protocol + query types**
   What: Add `2 Foundation/2.7 Utilities/CompletionProviding.swift` — `CompletionProviding` (`Sendable` protocol: `func completions(_ query: CompletionQuery) async -> [String]`) and `CompletionQuery` (`Sendable`: `language: WritingAssistLanguage`, `prefix: String`, `fullText: String`, `cursorOffset: Int`, `limit: Int`).
   Why: Content-agnostic seam so the editor reaches the corpus without importing module 9 — same pattern as `HelpContextResolving` (SR-1).

4. **Module 9 — author the parallel completion corpora (option 3)**
   What: Add a curated `completions.json` to each **Auto-Complete** submodule — `9.3 Markdown Help/`, `9.4 Html Help/`, and an ASCII source under `9.2 ASCII art Help/` (or reuse `9.1 ASCII Library` glyph names). **No Grammar (9.5) corpus** — Grammar has no Auto-Complete. Each is a flat list of completion entries `{ "text": "...", "weight": Int }` derived from topic `title` + `searchTerms` (+ selected body tokens), hand-tuned. Add a small generator note in each submodule's guide documenting how the list was derived (reproducibility).
   Why: Gives Auto-Complete real, controllable candidates without re-parsing prose at runtime (SR-3/4); keeps the help `body` reserved for More Context.

5. **Module 9 — implement the concrete corpus loader**
   What: Add `9 Resources/SputnikCompletionCorpus.swift` — an `actor` conforming to `CompletionProviding` that lazily loads each Markdown/HTML/ASCII `completions.json` on first use, builds a per-language prefix index (sorted/trie-like, case-folded), and returns the top-`limit` weighted matches for `query.prefix`. Spelling (`NSSpellChecker`, step 7) and Grammar (no Auto-Complete) are **not** sourced here; a `.grammar`/`.spelling` query returns `[]`.
   Why: Keeps corpus dispatch in the module that owns the data (SR-1); `actor` + lazy load satisfies concurrency and RAM rules (SW-1, SR-3).

6. **Editor 3.2/3.3/3.4 — extend each language provider with corpus completions**
   What: Give `MarkdownLanguageProvider`, `HTMLLanguageProvider`, and the ASCII `ASCIIArtLanguageProvider`/`BlockCompletion` an injected `completionProvider: any CompletionProviding`. In `generateSuggestion`, gate on `settings.writingAssist.isEnabled(.autoComplete, for: <language>)`; keep the existing pattern `suggest(...)` first, and when it returns `nil`, compute the current word prefix at the cursor and `await completionProvider.completions(...)`, showing the top candidate via the existing `ghostOverlay.show(_:)`.
   Why: Extends — does not duplicate — the existing ghost-text pipeline; the corpus is a fallback layer behind the curated patterns, all under one Auto-Complete gate.

7. **Editor 3.5 — add spelling Auto-Complete from the macOS dictionary**
   What: Add `3 Text Editor/3.5 Spelling and Grammar Checking/SpellingCompletionProvider.swift` — on keypress (debounced via `DebounceTimer`, gated on `writingAssist.isEnabled(.autoComplete, for: .spelling)`), compute the partial-word range and call `NSSpellChecker.shared.completions(forPartialWordRange:in:language:inSpellDocumentWithTag:)` (language from `settings.spellCheckLocale`), showing the top result through `GhostTextOverlay`.
   Why: Spelling predictions come from Apple's built-in dictionary per the agreed engine split; reuses the shared overlay and the checker's existing `spellDocumentTag`.

8. **Editor 3.5 — implement Instant Correct (Spelling + Grammar only)**
   What: In `SpellingGrammarChecker`, after a check produces an annotation with a high-confidence top correction, if `writingAssist.isEnabled(.instantCorrect, for: .spelling/.grammar)` is on, auto-apply that correction through the existing quickfix `applyFix` path once the user has moved past the word (word-boundary trigger), recording it as a normal undoable edit. The two gates are independent. Instant Correct is **never** offered for Markdown/HTML/ASCII — those cells do not exist (step 1) and the menu (step 10) never renders them.
   Why: Turns the existing quickfix infra into opt-in autocorrect without a parallel mechanism; word-boundary trigger avoids correcting mid-word. Confirmed scope per the user: Instant Correct is a Spelling/Grammar-only function.
   **Preserve existing manual-correction infra (do not remove or replace):** `EditorTextView.presentQuickfix(for:layoutManager:textContainer:)`, `applyFix(_:suggestion:)`, `dismissAnnotation(_:)`; the `QuickfixPopover` view with its `onFix`/`onDismiss` callbacks; `QuickfixPresenter.menu(for:wordRange:)`; and `SpellingGrammarChecker.dismiss(_:)`. Instant Correct is **additive** — it auto-invokes the same correction logic on a word-boundary trigger; the click-an-underline popover and its dismiss path must keep working unchanged when Instant Correct is off.

9. **Editor 3.1 — route keypresses through the gated providers + inject dependencies**
   What: In `EditorView`/`EditorTextView` wiring, construct `SputnikCompletionCorpus` once and inject it into the four providers + the new `SpellingCompletionProvider`; ensure `keyDown`'s existing Tab-accept / clear-on-other-key path covers corpus ghost text (it already operates on the shared overlay, so no change to acceptance logic). Confirm More Context cells gate the right-click items added by the separate pending plan (read `writingAssist.isEnabled(.moreContext, for:)` in that menu builder call).
   Why: Single injection point; keeps acceptance behaviour identical; wires the More Context gate without re-implementing the gesture.

10. **Foundation 2.4 / 2.0 — add the Writing Assistance menu**
    What: In `SputnikCommands.editMenu`, add a **Writing Assistance** `Menu` with one submenu per language, each containing a `Toggle` for the cells that `WritingAssistMatrix.applies(_:to:)` marks real, bound to `settings.writingAssist` via `setWritingAssist(_:for:_:)`. Keep the existing "Spelling and Grammar ▸ Check While Typing / Grammar Checking" toggles working (now computed over the matrix). Add an "All On / All Off" convenience pair.
    Why: Surfaces the matrix where users expect editing toggles; convenience action covers "all turned on together".

11. **Update module guides**
    What: 2.3 Settings — document `WritingAssistMatrix` + computed legacy bools (note ISS-011 resolution). 2.7 Utilities — add `CompletionProviding`/`CompletionQuery` + consumer list. 3.2/3.3/3.4 — note corpus-backed Auto-Complete behind the per-language gate. 3.5 — document spelling completion + Instant Correct. 9.x (9.2/9.3/9.4/9.5) — document `completions.json` and `SputnikCompletionCorpus`. 2.4 — note the Writing Assistance menu. Set `last_updated: 2026-06-09` on each; bump `status` where appropriate.
    Why: Guides are the source of truth; this feature changes the design intent of several modules.

12. **Verify**
    What: Visually confirm in the codebase: ghost completions appear per language and are gated correctly by each toggle; spelling completions come from the dictionary; Instant Correct applies for Spelling/Grammar only; toggles persist across relaunch; legacy menu toggles stay in sync with the matrix; Foundation has no module-9 import.
    Why: Matches the Success Condition.

13. **Commit and push to GitHub**
    What: `git status --short` to confirm no unrelated files; stage only the files in **Files Affected**; commit `[3 Text Editor] Inline predictive autocomplete + granular assist settings`; `git push origin <current branch>` (branch `feature/editor-quickfix-context-help`).
    Why: Version-controls the feature with a transparent, scoped commit; satisfies closeout.

## Risks and Constraints
- **Foundation change (flagged).** Touches 2.3, 2.4, 2.7 — ripples to every consumer. Mitigated by keeping additions purely additive and routing the legacy bools through the new matrix so nothing else changes.
- **Matrix vs legacy bools (ISS-011).** The computed-wrapper approach is load-bearing; if any consumer wrote the legacy bools expecting an independent store, audit it (only `SputnikCommands` and `SpellingGrammarChecker` do today).
- **Instant Correct scope (confirmed).** Instant Correct applies to **Spelling + Grammar only**; Markdown/HTML/ASCII Instant-Correct cells do not exist in the matrix and are never shown in the menu. Likewise More Context applies to **Grammar/Markdown/HTML only**. No reserved no-op cells remain.
- **Autocorrect UX risk.** Auto-applying corrections can fight the user; trigger only on word boundary, keep it undoable, and default the Instant-Correct cells **off**.
- **Corpus quality/RAM (SR-3).** Completion lists must stay compact and load lazily per language; do not hold all five corpora resident if only one mode is active.
- **Coordination.** The More Context cells depend on the two pending plans; this plan only adds their settings gate. Land order: matrix/settings here can merge first; the gate is a no-op until those plans wire the gesture.
- **No third-party packages (SR-5).** Prefix index is hand-rolled or uses Foundation collections only.

## Files Affected
- `2 Foundation/2.3 Settings/WritingAssistMatrix.swift` — new: matrix value type + enums.
- `2 Foundation/2.3 Settings/SettingsStore.swift` — add `writingAssist` + mutator; legacy bools become computed; migrate keys.
- `2 Foundation/2.7 Utilities/CompletionProviding.swift` — new: protocol + query/result types.
- `9 Resources/SputnikCompletionCorpus.swift` — new: concrete corpus actor.
- `9 Resources/9.3 Markdown Help/completions.json` — new corpus.
- `9 Resources/9.4 Html Help/completions.json` — new corpus.
- `9 Resources/9.2 ASCII art Help/completions.json` (or reuse 9.1 library) — new corpus.
- `3 Text Editor/3.2 Markdown Language/MarkdownLanguageProvider.swift` — corpus fallback + gate.
- `3 Text Editor/3.4 HTML Langugage/HTMLLanguageProvider.swift` — corpus fallback + gate.
- `3 Text Editor/3.3 ASCII art/ASCIIArtLanguageProvider.swift` (+ `BlockCompletion.swift`) — corpus fallback + gate.
- `3 Text Editor/3.5 Spelling and Grammar Checking/SpellingCompletionProvider.swift` — new: dictionary completion.
- `3 Text Editor/3.5 Spelling and Grammar Checking/SpellingGrammarChecker.swift` — Instant Correct apply path + gate.
- `3 Text Editor/3.1 Text/EditorView.swift` (+ `EditorTextView.swift`) — inject corpus/providers; More Context gate.
- `2 Foundation/2.0 App Overview/SputnikCommands.swift` — Writing Assistance menu.
- Module guides: `2.3 Settings`, `2.4 UI and UX`, `2.7 Utilities`, `3.2`, `3.3`, `3.4`, `3.5`, `9.2`, `9.3`, `9.4`, `9.5` — `last_updated: 2026-06-09`.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] ISS-011 marked Resolved; ISS-004 progress noted in `References/Issues.md`
- [ ] Changes committed: `[3 Text Editor] Inline predictive autocomplete + granular assist settings`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
