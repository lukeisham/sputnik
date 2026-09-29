---
plan: Separate Grammar Help from Style Help
module: 9 Resources, 2 Foundation (2.0, 2.3, 2.4)
created: 2026-06-28
status: complete
related_issues: none
---

## Purpose

Extract the "Style" category out of the existing 9.5 Grammar Help sub-module into a brand-new 9.9 Style Help sub-module, wire it up as a first-class help panel with its own Foundation enum values, menus, settings, and context-lookup path — and populate the Style content based on content from `Style/style_open_source.m`, which is *The Elements of Style* by William Strunk Jr. (1919, public domain via Project Gutenberg, 2,759 lines / ~105 KB).

## Success Condition

- `Help > Style Guide` opens a dedicated Style Help panel (separate tab bar, separate index).
- `Help > Grammar Help` contains only pure grammar topics — no style-category entries remain.
- Right-click "Look Up in Style Guide" works from Text Editor, Markdown Preview, and HTML Preview.
- Edit > Writing Assistance > Style submenu exists with a More Context toggle.
- Help > More Context > Style toggle exists.
- Help > Interaction > Style toggle exists.
- Settings > Spelling & Grammar tab is unchanged; no style settings required (style has no
  Instant Correct or Auto-Complete axis).
- `9 Resources/Package.swift` bundles `9.9 Style Help` resources.
- `Style/style_open_source.md` content is parsed into per-topic `.md` files under
  `9 Resources/9.9 Style Help/`.
- All affected Module Guides updated; build is clean.

---

## Steps

### Foundation Layer

1. **Add `HelpTopic.style` to Foundation**

   What: In `2 Foundation/2.4 UI and UX/HelpTopic.swift`, add a new case `.style` to the
   `HelpTopic` enum with `title = "Style Guide"`. Update the `title` switch to include it.

   Why: Every help panel requires a `HelpTopic` case so `AppState.requestedHelpTopic` can
   route to it and `HelpMenuGroup` can trigger it. Foundation owns the enum (SR-1).

2. **Add `WritingAssistLanguage.style` to Foundation**

   What: In `2 Foundation/2.3 Settings/WritingAssistMatrix.swift`:
   - Add `.style` case to `WritingAssistLanguage` (after `.grammar`).
   - Update `WritingAssistMatrix.applies(_:to:)`:
     - `.moreContext` → true for `.style`
     - `.interaction` → true for `.style`
     - `.instantCorrect` → false for `.style` (style advice is guidance, not auto-correct)
     - `.autoComplete` → false for `.style`

   Why: The writing-assist matrix is the single source of truth for per-language feature
   toggles (ISS-011). Style needs its own row so More Context and Interaction can be toggled
   independently of Grammar.

   Note: `WritingAssistLanguage` is `CaseIterable` — adding `.style` automatically includes
   it in `WritingAssistMatrix.allOn()` / `allOff()` and in the `default` preset (which will
   default style More Context to on, Interaction to on, per the existing formula).

3. **Update `EditMenuGroup` Writing Assistance submenu**

   What: In `2 Foundation/2.0 App Overview/EditMenuGroup.swift`, add a "Style" submenu to
   `writingAssistanceMenu` (after "Grammar"):
   ```swift
   Menu("Style") {
       toggleCell(.moreContext, .style, label: "More Context")
   }
   ```

   Why: Every applicable writing-assist cell needs a menu entry (ISS-011 contract). Style
   has only one applicable axis (moreContext); there is no instantCorrect or autoComplete.
   Interaction is in HelpMenuGroup, not here.

4. **Update `HelpMenuGroup` — Help button, More Context, Interaction**

   What: In `2 Foundation/2.0 App Overview/HelpMenuGroup.swift`:
   a. Add a "Style Guide" button after "Grammar Help":
      ```swift
      Button("Style Guide") {
          appState.requestedHelpTopic = .style
      }
      ```
   b. In `moreContextSubmenu`, add "Style" before the "Divider":
      ```swift
      Menu("Style") {
          toggleMoreContext(.style)
      }
      ```
   c. In `interactionSubmenu`, add "Style" (Style Help can be a right-click lookup target):
      ```swift
      Menu("Style") {
          toggleInteraction(.style)
      }
      ```

   Why: Help panel triggers live in HelpMenuGroup; More Context and Interaction submenu
   entries must mirror each applicable `WritingAssistLanguage` case (ISS-142 contract).

5. **Update `KeyboardShortcutCatalog`**

   What: In `2 Foundation/2.0 App Overview/KeyboardShortcutCatalog.swift`, add an entry
   in the Help group for "Style Guide" (no shortcut key — same as other help items that
   have no keyboard shortcut beyond the menu itself).

   Why: The catalog is a hand-maintained mirror of all menu items (SR-1 reference catalog);
   any new menu button must be reflected here to keep Settings > Shortcuts accurate.

---

### Module 9 — Content Migration

6. **Move existing style-category Grammar topics to new `9.9 Style Help` directory**

   What:
   - Create `9 Resources/9.9 Style Help/` directory.
   - Move all 8 `.md` files from `9 Resources/9.5 Grammar Help/style/` into
     `9 Resources/9.9 Style Help/`:
       - `active-vs-passive.md`
       - `avoiding-cliches.md`
       - `conciseness.md`
       - `parallelism.md`
       - `rhythm-and-flow.md`
       - `sentence-variety.md`
       - `tone-and-register.md`
       - `word-choice-and-colour.md`
   - Delete the now-empty `9 Resources/9.5 Grammar Help/style/` directory.

   Why: These 8 topics are the seed of the Style Help content. Moving them decouples them
   from Grammar so neither index references the other's topics. The Grammar Help index
   entries for these topics will be removed in Step 8.

7. **Author Style topics from `Style/style_open_source.md`**

   The source is *The Elements of Style* by William Strunk Jr. (1919, public domain). Parse
   it into per-topic `.md` files following the Grammar Help format (H2 title, body with
   ✅/❌ examples where applicable). Place files in `9 Resources/9.9 Style Help/` alongside
   the 8 migrated topics.

   **Topics to extract — Chapter II: Elementary Rules of Usage** (`category: "usage"`)
   These 7 rules are punctuation/usage rules. Several overlap with Grammar Help punctuation
   topics but are presented here in Strunk's style-guide context — they should remain in
   Style Help, not Grammar Help, to keep the source attribution clear.
   - `rule-01-possessive-s` — Form the possessive singular by adding 's
   - `rule-02-serial-comma` — Serial comma in a series of three or more
   - `rule-03-parenthetic-commas` — Enclose parenthetic expressions between commas
   - `rule-04-comma-before-conjunction` — Comma before a co-ordinating conjunction
   - `rule-05-comma-splice` — Do not join independent clauses by a comma
   - `rule-06-no-sentence-fragments` — Do not break sentences in two
   - `rule-07-participial-phrase` — Participial phrase must refer to the grammatical subject

   **Topics to extract — Chapter III: Elementary Principles of Composition** (`category: "composition"`)
   - `rule-08-paragraph-unit` — Make the paragraph the unit of composition
   - `rule-09-topic-sentence` — Begin each paragraph with a topic sentence
   - `rule-10-active-voice` — Use the active voice (note: overlaps with migrated `active-vs-passive.md`; merge the two files into one richer topic)
   - `rule-11-positive-form` — Put statements in positive form
   - `rule-12-concrete-language` — Use definite, specific, concrete language
   - `rule-13-omit-needless-words` — Omit needless words (note: overlaps with `conciseness.md`; merge)
   - `rule-14-avoid-loose-sentences` — Avoid a succession of loose sentences (note: relates to `sentence-variety.md`; link as relatedTopic)
   - `rule-15-parallel-structure` — Express co-ordinate ideas in similar form (note: overlaps with `parallelism.md`; merge)
   - `rule-16-related-words-together` — Keep related words together
   - `rule-17-tense-in-summaries` — In summaries, keep to one tense
   - `rule-18-emphatic-position` — Place the emphatic words of a sentence at the end

   **Topics to extract — Chapter IV: Matters of Form** (`category: "form"`)
   - `form-headings` — Headings and manuscript formatting
   - `form-numerals` — Numerals vs. spelled-out numbers
   - `form-parentheses` — Punctuating parenthetic expressions
   - `form-quotations` — Formal quotations, colons, and quotation marks
   - `form-references` — Citations and references in scholarly writing
   - `form-syllabication` — Word division / syllabication
   - `form-titles` — Italics and capitalization for titles

   **Topics to extract — Chapter V: Commonly Misused Words** (`category: "word-usage"`)
   Chapter V is a long alphabetical glossary (~60 entries). Create one topic per entry
   rather than a single monolithic topic — this makes right-click context lookup effective
   (e.g. selecting "which" finds the `which-vs-that` topic; selecting "affect" finds
   `affect-vs-effect`). Key entries to become individual topics include:
   - `misuse-affect-effect`, `misuse-as-like`, `misuse-case`, `misuse-data`,
     `misuse-due-to`, `misuse-each-and-every-one`, `misuse-etc`, `misuse-fact-that`,
     `misuse-factor`, `misuse-feature`, `misuse-fix`, `misuse-however`,
     `misuse-interesting`, `misuse-lay-lie`, `misuse-less-fewer`,
     `misuse-loan-lend`, `misuse-masterful-masterly`, `misuse-nature`,
     `misuse-one-of-the-most`, `misuse-people-persons`, `misuse-possess`,
     `misuse-respective-respectively`, `misuse-shall-will`, `misuse-so`,
     `misuse-split-infinitive`, `misuse-state`, `misuse-system`, `misuse-thanking-you`,
     `misuse-that-which`, `misuse-they-their-singular`, `misuse-type`,
     `misuse-unique`, `misuse-very`, `misuse-while`, `misuse-who-whom`
   (Full list in Chapter V — author all entries present in the source.)

   **Merge notes for migrated topics** (from Step 6):
   - `active-vs-passive.md` → merge content with Rule 10 into `rule-10-active-voice.md`
   - `conciseness.md` → merge with Rule 13 into `rule-13-omit-needless-words.md`
   - `parallelism.md` → merge with Rule 15 into `rule-15-parallel-structure.md`
   - `avoiding-cliches.md`, `rhythm-and-flow.md`, `sentence-variety.md`,
     `tone-and-register.md`, `word-choice-and-colour.md` — keep as standalone topics,
     set `category: "composition"` or `"word-usage"` as appropriate, link Rule overlaps
     via `relatedTopics`.

   Why: The Style Help panel needs a comprehensive topic library to be useful, and
   Strunk's structure provides the authoritative content. Individual per-entry topics for
   Chapter V maximise context-lookup hit rate from right-click word selection (SR-1:
   `searchTerms` per topic maps to specific words/phrases the user may select).

7b. **Author supplementary topics covering gaps not addressed by Strunk (1919)**

    Strunk is the foundation but is 107 years old. The following topics extend the Style
    Help library to cover modern writing concerns. Place all files in
    `9 Resources/9.9 Style Help/` and include them in `style_help_index.json`.

    **Structural topics** (`category: "structure"`) — a fifth category alongside the four
    Strunk categories. Add `"structure"` to the valid category list in Step 9 and Step 10.
    - `transitions` — Connecting paragraphs and sections (however, therefore, in contrast,
      building on this); how weak transitions signal unclear thinking
    - `signposting` — Explicit roadmapping in longer documents ("This section argues…",
      "Having established X, we now turn to…"); when to use it and when it adds clutter
    - `introductions` — The three jobs of an introduction: orient the reader, state the
      claim, earn attention; the funnel and the direct opening
    - `conclusions` — What a conclusion must do beyond summary: the "so what", the call to
      action, the resonant close; avoiding the trailing-off ending
    - `argument-structure` — Claim, evidence, warrant; the Toulmin model in plain terms;
      how to distinguish assertion from argument

    **Voice and audience topics** (`category: "voice"`)
    - `audience-awareness` — Writing to a specific reader: what do they already know? What
      do they need? How does audience shift diction, structure, and assumed context?
    - `consistent-voice` — How to find and maintain a voice across a document; the danger
      of voice-switching between formal and casual within a single piece
    - `formal-vs-informal` — Extend the migrated `tone-and-register.md` with concrete
      decision criteria: contractions, second person, colloquialisms, hedging language

    **Modern usage topics** (`category: "word-usage"`)
    - `inclusive-language` — Gender-neutral pronouns (singular they), avoiding
      assumptions about readers, bias-free language; why this is a clarity issue as well as
      a courtesy one
    - `avoiding-jargon` — When technical language is precise (keep it) vs when it excludes
      or obscures (replace it); the plain-language test: "could a non-specialist follow this?"
    - `plain-language` — The Plain English movement; Flesch readability as a diagnostic
      tool; the preference for short words, active voice, and concrete nouns in public-facing
      writing

    **Punctuation gaps** (`category: "usage"`) — not in Strunk's 1919 edition
    - `em-dash` — Em dash vs en dash vs hyphen: when to use each, spacing conventions,
      and the em dash as a strong parenthetic alternative to commas and parentheses
    - `ellipsis` — Ellipsis in quotation (omitting words), ellipsis for trailing off in
      dialogue; three dots vs four; avoid overuse in formal writing
    - `colon-usage` — Colon to introduce a list, a quotation, or a clause that explains;
      capitalisation after a colon; colon vs semicolon decision

    **Additional misused word pairs** (`category: "word-usage"`) — gaps in Strunk's Ch. V
    - `misuse-comprise-compose` — "The team comprises five members" vs "Five members compose the team"
    - `misuse-imply-infer` — Speaker implies; listener infers
    - `misuse-disinterested-uninterested` — Impartiality vs indifference
    - `misuse-literally` — Reserved for literal truth; "literally exploded" vs "exploded"
    - `misuse-hopefully` — Sentence adverb use and the style objection to it
    - `misuse-between-among` — Between two; among three or more (and the exceptions)
    - `misuse-further-farther` — Distance (farther) vs degree (further)
    - `misuse-due-to-because-of` — Adjectival vs adverbial use
    - `misuse-fewer-less` — Countable (fewer) vs uncountable (less); the supermarket sign rule
    - `misuse-that-who` — Restrictive clauses for persons use "who", not "that"
    - `misuse-continual-continuous` — Repeated interruptions (continual) vs unbroken (continuous)
    - `misuse-nauseous-nauseated` — Causing nausea vs feeling nausea (and the prescriptive debate)

    Why: Strunk alone leaves significant gaps in audience, structure, modern conventions, and
    punctuation. These supplementary topics are original content (not sourced from Strunk) and
    must be authored fresh. They follow the same `.md` format and `searchTerms` discipline as
    all other Style Help topics. The `"structure"` category addition requires updating
    `StyleHelpContent.swift` (Step 10) to include it in the valid category list.

8. **Remove style-category entries from `grammar_help_index.json`**

   What: In `9 Resources/9.5 Grammar Help/grammar_help_index.json`, delete all entries
   whose `"category"` field is `"style"` (the 8 topics migrated in Step 6). Verify the
   remaining entries are well-formed JSON and all `relatedTopics` cross-references still
   resolve within the grammar topic set.

   Why: GrammarHelpIndex loads and searches this file; style topics remaining in it would
   appear in Grammar Help search results after the panel is split.

---

### Module 9 — New Swift Source Files (9.9 Style Help)

9. **Create `style_help_index.json`**

   What: Author `9 Resources/9.9 Style Help/style_help_index.json` following the exact
   same schema as `grammar_help_index.json`:
   ```json
   [
     {
       "id": "active-vs-passive",
       "title": "Active vs Passive Voice",
       "category": "voice",
       "body": "...",
       "searchTerms": ["passive voice", "active voice", "was written by", "by the"],
       "relatedTopics": ["conciseness", "sentence-variety"],
       "structuralLevel": "lexical"
     },
     ...
   ]
   ```
   Include one entry per `.md` file (migrated + all new ones from Steps 7 and 7b). The five
   valid category values are: `"usage"`, `"composition"`, `"form"`, `"word-usage"`,
   `"structure"`.
   Set `searchTerms` carefully — they drive right-click context lookup. For word-usage
   entries, `searchTerms` should include the exact words/phrases discussed (e.g. the
   `misuse-affect-effect` entry gets `["affect", "effect", "affects", "effects"]`).

   Why: `StyleHelpIndex` will load this file on first access, exactly as `GrammarHelpIndex`
   loads `grammar_help_index.json`. A well-curated `searchTerms` array is the difference
   between useful and useless context lookup.

10. **Create `StyleHelpContent.swift`**

    What: Create `9 Resources/Sources/9.9 Style Help/StyleHelpContent.swift`. Model it
    on `GrammarHelpContent.swift` with these differences:
    - Type name: `StyleHelpContent` (conforms to `HelpTopicProtocol`)
    - No `structuralLevel` field (not needed — Style topics are always guidance-level)
    - Valid `category` string values: `"usage"`, `"composition"`, `"form"`, `"word-usage"`,
      `"structure"`, `"voice"` (Steps 7 and 7b define all categories)

    Why: `SputnikHelpPanel` is parameterised over `Topic: HelpTopicProtocol` — a concrete
    topic type is required per panel kind (SR-1: each help kind owns its model).

11. **Create `StyleHelpIndex.swift`**

    What: Create `9 Resources/Sources/9.9 Style Help/StyleHelpIndex.swift` as an `actor`:
    - Loads `style_help_index.json` from `Bundle.module` on first access.
    - Provides `search(query:) -> [StyleHelpContent]` scoring by title/body/searchTerms.
    - Provides `topic(id:) -> StyleHelpContent?`.
    - Mirror the `GrammarHelpIndex` structure exactly; the only differences are the type
      name and the JSON filename.

    Why: All help indexes are actors (module 9 invariant) — index access goes through
    `await` to keep the main actor clear (SR-4).

12. **Create `StyleHelpCoordinator.swift`**

    What: Create `9 Resources/Sources/9.9 Style Help/StyleHelpCoordinator.swift` as a
    `@MainActor` class:
    - `static let shared = StyleHelpCoordinator()`
    - `func lookup(word: String, source: StyleHelpSource) async -> StyleHelpLookupResult?`
      — scores by `searchTerms` exact/substring/title match; returns the best match.
    - No `GrammarSelectionAnalyzer` integration needed — style lookup is always lexical.
    - `var onNavigate: ((HelpRequest) -> Void)?` — wired by the panel view on `.task`.
    - Mirror `GrammarHelpCoordinator` without the structural-aware lookup complexity.

    Why: The coordinator pattern isolates context-lookup logic from the panel view (SR-6).
    It is the single bridge between `SputnikHelpContextResolver` and the Style panel.

13. **Create `StyleHelpPanelView.swift`**

    What: Create `9 Resources/Sources/9.9 Style Help/StyleHelpPanelView.swift`:
    - Wraps `SputnikHelpPanel<StyleHelpContent, StyleTopicContentView>`.
    - `StyleTopicContentView` renders topic body with ✅/❌ line-level formatting
      (same renderer as `GrammarHelpPanelView` — share or copy the render logic).
    - Observes `AppState.requestedHelpTarget` for `.style` requests and navigates to the
      resolved topic ID.
    - Wires `StyleHelpCoordinator.shared.onNavigate` in `.task`.

    Why: Each help kind needs its own panel view to register with the Foundation 2.4
    panel registry and produce the correct content (SR-1; GrammarHelpPanelView precedent).

14. **Update `SputnikHelpContextResolver.swift`**

    What: In `9 Resources/Sources/SputnikHelpContextResolver.swift`, add a `.style` case
    to the `switch query.kind` block:
    ```swift
    case .style:
        let result = await StyleHelpCoordinator.shared.lookup(
            word: query.selectedText,
            source: .editor
        )
        topicID = result?.primaryTopic.id
    ```

    Why: The resolver is the single dispatch point for all right-click context lookups
    (ISS-008 design). Adding `.style` here gives Text Editor, Markdown Preview, and HTML
    Preview "Look Up in Style Guide" capability with no changes to those modules (SR-1).

15. **Update `9 Resources/Package.swift`**

    What: Add a `.process("9.9 Style Help")` entry to the `resources:` array in
    `9 Resources/Package.swift` (alongside the existing `9.5 Grammar Help` entry).

    Why: Without this entry the `style_help_index.json` and topic `.md` files are not
    bundled — `Bundle.module.url(forResource:)` returns nil and the panel loads zero topics
    (ISS-045 is the canonical example of this footgun).

---

### Module 9 — Grammar Cleanup

16. **Update `GrammarHelpContent.swift` category list**

    What: In `9 Resources/Sources/9.5 Grammar Help/GrammarHelpContent.swift`, remove
    `"style"` from the `category` enum / comment / documentation to reflect that Grammar
    Help no longer hosts style topics. Valid Grammar categories after this change:
    `punctuation`, `grammar`, `spelling`, `usage`, `edge-cases`, `mechanics`,
    `sentence-structure`.

    Why: Keeping "style" in the Grammar category list would mislead future developers into
    adding style topics back to Grammar Help (SR-6: each file's responsibility must be clear).

---

### Module Guide Updates

17. **Update Module Guide 9.5 (Grammar Help)**

    What: Edit `1 Setup/Module Guides/9 Resources/9.5 Grammar Help/guide.md`:
    - Remove "style" from the category list in Technical Summary.
    - Remove the 8 migrated style topics from any content lists.
    - Update `last_updated: 2026-06-28`, `status: active`.

    Why: The guide is the source of truth for the module; it must not reference content
    that has moved (SR-1; guide discipline).

18. **Create Module Guide 9.9 (Style Help)**

    What: Create `1 Setup/Module Guides/9 Resources/9.9 Style Help/guide.md` using the
    standard Module Guide format. Model on the 9.5 guide with these differences:
    - Purpose: "Provide a library of English writing-style reference topics derived from the
      open-source style guide, browsable in a dedicated panel and accessible via right-click
      context lookup from Text Editor, Markdown Preview, and HTML Preview."
    - Source files: StyleHelpContent, StyleHelpIndex, StyleHelpCoordinator, StyleHelpPanelView
    - Content source: `Style/style_open_source.md` → `9 Resources/9.9 Style Help/*.md`
    - No `GrammarSelectionAnalyzer` dependency (lookup is lexical-only).
    - `status: active`, `last_updated: 2026-06-28`.

    Why: Every sub-module requires a Module Guide before code is touched (skill requirement).

19. **Update Module Guide 9 (root)**

    What: Edit `1 Setup/Module Guides/9 Resources/guide.md`:
    - Add 9.9 Style Help to the Source Files table.
    - Add `StyleHelpCoordinator`, `StyleHelpIndex`, `StyleHelpContent`, `StyleHelpPanelView`
      to the diagram and Technical Summary.
    - Update `SputnikHelpContextResolver` description to mention `.style` dispatch.
    - Update `last_updated: 2026-06-28`.

    Why: The root Module 9 guide must reflect all sub-modules it coordinates.

---

## Risks and Constraints

- **Chapter V (Commonly Misused Words) has ~60 entries.** These should each become a
  separate `.md` topic file for best context-lookup coverage. This is the most time-intensive
  authoring step; it is purely additive and can be done incrementally after the panel is
  wired up and functional with Chapter II–IV topics.
- **Foundation changes have global ripple.** Adding `.style` to `WritingAssistLanguage` and
  `HelpTopic` means any switch statement in any module that exhaustively switches on these
  enums will require updating. Run a build after Steps 1–2 to surface these.
- **`grammar_help_index.json` integrity.** After removing 8 style entries, verify all
  `relatedTopics` arrays in the remaining grammar entries do not reference a style topic ID.
  If any do, update those references or remove the cross-link.
- **ISS-011 `WritingAssistMatrix.default` preset.** Adding `.style` to `WritingAssistLanguage`
  means the `default` preset's constructor loop will automatically include `.style` More
  Context = on and Interaction = on. This is the correct default. Verify no code
  special-cases `WritingAssistLanguage.allCases.count`.
- **No `SpellingGrammarChecker` changes.** Style does not have an Instant Correct axis —
  the existing `SpellingGrammarChecker` in module 3.5 does not need to know about style.
  Only the help/context path is new.

## Files Affected

**Foundation (2.0 App Overview)**
- `2 Foundation/2.0 App Overview/EditMenuGroup.swift` — add Style submenu
- `2 Foundation/2.0 App Overview/HelpMenuGroup.swift` — add Style Guide button + toggles
- `2 Foundation/2.0 App Overview/KeyboardShortcutCatalog.swift` — add catalog entry

**Foundation (2.3 Settings)**
- `2 Foundation/2.3 Settings/WritingAssistMatrix.swift` — add `.style` language + applicability

**Foundation (2.4 UI and UX)**
- `2 Foundation/2.4 UI and UX/HelpTopic.swift` — add `.style` case

**9 Resources — New files**
- `9 Resources/9.9 Style Help/style_help_index.json` — topic index (new)
- `9 Resources/9.9 Style Help/*.md` — topic content files (~70–80 total: 8 migrated, ~29 from Strunk Ch. II–IV, ~34 from Strunk Ch. V, ~27 supplementary from Step 7b)
- `9 Resources/Sources/9.9 Style Help/StyleHelpContent.swift` — topic model (new)
- `9 Resources/Sources/9.9 Style Help/StyleHelpIndex.swift` — index actor (new)
- `9 Resources/Sources/9.9 Style Help/StyleHelpCoordinator.swift` — lookup coordinator (new)
- `9 Resources/Sources/9.9 Style Help/StyleHelpPanelView.swift` — panel view (new)

**9 Resources — Modified files**
- `9 Resources/Package.swift` — add `.process("9.9 Style Help")` resource entry
- `9 Resources/Sources/SputnikHelpContextResolver.swift` — add `.style` dispatch
- `9 Resources/9.5 Grammar Help/grammar_help_index.json` — remove 8 style entries
- `9 Resources/Sources/9.5 Grammar Help/GrammarHelpContent.swift` — remove style category

**9 Resources — Deleted / Moved**
- `9 Resources/9.5 Grammar Help/style/*.md` → `9 Resources/9.9 Style Help/`

**Module Guides**
- `1 Setup/Module Guides/9 Resources/9.5 Grammar Help/guide.md` — update
- `1 Setup/Module Guides/9 Resources/9.9 Style Help/guide.md` — create (new)
- `1 Setup/Module Guides/9 Resources/guide.md` — add 9.9 entry

## Closeout

- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (Help > Style Guide opens correct panel; Grammar Help has no style topics)
- [ ] `style_open_source.md` parsed into topic files (Step 7 complete)
- [ ] Right-click "Look Up in Style Guide" tested from Text Editor
- [ ] Build is clean after Foundation enum additions (no exhaustive-switch errors missed)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[9 Resources + 2 Foundation] Separate Grammar Help from Style Help`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
