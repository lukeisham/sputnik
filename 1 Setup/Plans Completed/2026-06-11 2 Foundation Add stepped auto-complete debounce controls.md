---
plan: Add stepped auto-complete debounce controls
module: 2 Foundation (2.3 Settings)
created: 2026-06-11
status: complete
related_issues: ISS-050
---

## Purpose
Replace the four raw-number debounce fields for auto-complete ghost-text (Markdown, HTML, ASCII, and spelling completion) with stepped "Instant → 3 s" pickers, and split the spelling debounce field so the squiggly-underline checker is not affected.

## Success Condition
- Opening Settings shows four labelled stepped controls (Markdown / HTML / ASCII / Spelling auto-complete), each offering the 7 steps: Instant (0 s), 0.5, 1, 1.5, 2, 2.5, 3 s.
- Changing a control takes effect immediately in the corresponding language provider (ghost text response changes).
- The squiggly-underline checker continues to use its own `spellCheckDebounceInterval` field, unaffected by the new spelling completion control.
- The old free-text debounce number fields are gone.
- The chosen step value survives app quit/relaunch.
- No force-unwraps; all step-to-TimeInterval mapping is exhaustive with no default fallback needed.

## Steps

- [x] 1. **Add `AutoCompleteDebounceStep` enum to Foundation (2.3 Settings)**
   What: Create `2 Foundation/2.3 Settings/AutoCompleteDebounceStep.swift`. Define a `CaseIterable`, `Codable`, `Sendable` enum with 7 cases: `.instant`, `.half`, `.one`, `.oneHalf`, `.two`, `.twoHalf`, `.three`. Add a computed `timeInterval: TimeInterval` property returning `0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0` respectively. Add a `label: String` property returning human-readable strings (`"Instant"`, `"0.5 s"` … `"3 s"`). Add a static `default: AutoCompleteDebounceStep = .half`.
   Why: A named enum is exhaustive, needs no range validation, and is `Codable` for persistence — cleaner than storing a raw `TimeInterval` and clamping at read time. Owned once in Foundation (SR-1).

- [x] 2. **Add four new `AutoCompleteDebounceStep` fields to `SettingsStore`**
   What: In `SettingsStore.swift`, add four stored properties: `markdownAutoCompleteStep: AutoCompleteDebounceStep = .default`, `asciiAutoCompleteStep: AutoCompleteDebounceStep = .default`, `htmlAutoCompleteStep: AutoCompleteDebounceStep = .default`, `spellingAutoCompleteStep: AutoCompleteDebounceStep = .default`. Add four corresponding `DefaultsKey` entries and four `set*` mutators following the existing pattern. Add four load branches in `loadFromDefaults()`.
   Why: Each provider gets its own independent step value (user decision: per-language steppers). Each mutator persists immediately via `PersistenceService`, matching the existing pattern.

- [x] 3. **Resolve ISS-050 — wire `SpellingCompletionProvider` to the new step field**
   What: In `SpellingCompletionProvider.swift`, change the `debounce.schedule(delay:)` call (line 45) from `settings.spellCheckDebounceInterval` to `settings.spellingAutoCompleteStep.timeInterval`. Mark ISS-050 resolved.
   Why: This is the fix for the dual-purpose field. `SpellingGrammarChecker` (squiggly underline) continues to read `spellCheckDebounceInterval` unchanged; `SpellingCompletionProvider` (ghost-text completion) now reads the new step field. Single meaning per field (SR-1).

- [x] 4. **Wire `MarkdownLanguageProvider`, `HTMLLanguageProvider`, and `ASCIIArtLanguageProvider` to the new step fields**
   What: In each of the three provider files, replace the `settings.*DebounceInterval` read inside `debounce.schedule(delay:)` with `settings.*AutoCompleteStep.timeInterval` (e.g. `settings.markdownAutoCompleteStep.timeInterval`).
   Why: The providers now read the typed enum value, which is always valid — no need for range clamping.

- [x] 5. **Build a reusable `DebounceStepPicker` SwiftUI view**
   What: Create `2 Foundation/2.4 UI and UX/DebounceStepPicker.swift`. A small SwiftUI `View` accepting a `Binding<AutoCompleteDebounceStep>` and a `String` label. Renders as a `Picker` (`.segmented` or `.menu` style — see Risk note) listing all `AutoCompleteDebounceStep.allCases` with their `.label`. No logic beyond binding and display.
   Why: All four controls share identical behaviour; one reusable view avoids duplication (SR-1, SR-6). Living in 2.4 UI/UX means it can be used by any module's settings tab.

- [x] 6. **Replace the four old debounce text fields in the Settings window**
   What: In `App-Sputnik/SputnikApp.swift`, in the `EditorTab` body, remove the three `LabeledContent("… debounce (s)")` / `TextField` blocks for Markdown, ASCII, and HTML. Replace each with a `DebounceStepPicker` bound to the matching new step field via `Binding(get:set:)`. In `SpellingTab`, remove the `LabeledContent("Spell-check debounce (s)")` `TextField` block and add a `DebounceStepPicker` for `spellingAutoCompleteStep`. Add a brief section label ("Auto-complete delay") above the pickers to distinguish them from the squiggly-underline toggle row above.
   Why: Old free-text fields are removed (user decision). The section label makes clear these controls affect auto-complete only, not the squiggly checker.

- [x] 7. **Update the 2.3 Settings Module Guide**
   What: In `1 Setup/Module Guides/2 Foundation/2.3 Settings/guide.md`, replace the four raw `TimeInterval` entries in the "State owned" list with the four new `AutoCompleteDebounceStep` entries. Add `AutoCompleteDebounceStep` and `DebounceStepPicker` to the "Key types" list. Update `last_updated` to `2026-06-11`.
   Why: The guide is the source of truth; it must stay in sync with the implementation (working convention).

## Risks and Constraints
- **Picker style choice:** `.segmented` with 7 items is very wide at 400 pt+; a `.menu` (dropdown) picker is more space-efficient but less scannable. Use `.menu` unless the Settings form has a wide enough column.
- **Existing persisted values:** Users who previously saved a raw `TimeInterval` will have no `AutoCompleteDebounceStep` key in `UserDefaults`, so `loadFromDefaults()` will simply fall back to `.default` (0.5 s). No migration needed — the old raw interval keys (markdown/ascii/html) remain in `UserDefaults` harmlessly.
- **`spellCheckDebounceInterval` not removed:** The existing `spellCheckDebounceInterval` property, its `DefaultsKey`, mutator, and load branch stay untouched — the squiggly checker still reads it. Do not remove it.
- **SR-1:** `AutoCompleteDebounceStep` must live in Foundation (2.3 Settings), not in module 3, even though its consumers are in module 3. Foundation owns shared tokens.
- **SW-1:** No `DispatchQueue` calls; debounce scheduling in providers already uses `Task { @MainActor … }` via `DebounceTimer`.

## Files Affected
- `2 Foundation/2.3 Settings/AutoCompleteDebounceStep.swift` — **new file**: the 7-step enum with `timeInterval` and `label`
- `2 Foundation/2.3 Settings/SettingsStore.swift` — add 4 step properties, keys, mutators, load branches
- `2 Foundation/2.4 UI and UX/DebounceStepPicker.swift` — **new file**: reusable SwiftUI picker view
- `3 Text Editor/3.5 Spelling and Grammar Checking/SpellingCompletionProvider.swift` — read `spellingAutoCompleteStep.timeInterval` (resolves ISS-050)
- `3 Text Editor/3.2 Markdown Language/MarkdownLanguageProvider.swift` — read `markdownAutoCompleteStep.timeInterval`
- `3 Text Editor/3.4 HTML Langugage/HTMLLanguageProvider.swift` — read `htmlAutoCompleteStep.timeInterval`
- `3 Text Editor/3.3 ASCII art/ASCIIArtLanguageProvider.swift` — read `asciiAutoCompleteStep.timeInterval`
- `App-Sputnik/SputnikApp.swift` — replace 4 debounce `TextField` rows with `DebounceStepPicker` rows
- `1 Setup/Module Guides/2 Foundation/2.3 Settings/guide.md` — update state list + key types

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation] Add stepped auto-complete debounce controls`
- [ ] Pushed to GitHub
- [x] Plan moved to Plans Completed/
