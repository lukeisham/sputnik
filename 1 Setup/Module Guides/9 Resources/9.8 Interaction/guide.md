---
module: 9.8 Interaction
status: stable
last_updated: 2026-06-16
last_verified: 2026-06-16
open_issues:
---

## Purpose

Detect **special elements** at the user's selection — from a combination of a **syntax term** (structural pattern) and a **contextual heading** — resolve them against a declarative **special-element registry**, and **auto-insert** the Resource content each element's slots require into the document. Parallel to More-Context, but writes into the document instead of opening a Help panel, and **replaces** More-Context on the right-click menu when a special element is detected.

## Diagram

```
User selects text + right-clicks
       │
       ▼
SelectionContextMenu (Foundation 2.7) ──── precedence gate:
       │   detector.detect(...) ≠ nil  AND  Interaction enabled?
       │        │ yes → "Interact with…"        │ no → "More Context: …" (unchanged)
       ▼
SpecialElementDetector  (Signal 1: syntax term  +  Signal 2: nearest heading)
       │     └─ SpecialElementRegistry.resolve(syntaxTerm, contextHeading) → definitionID
       │  SpecialElement { kind (container), definitionID (semantic), syntaxTerm, contextHeading, ranges }
       ▼
InteractionCoordinator
       │
       ├─ InteractionProvider (actor)
       │     ├ PRIMARY  registry definition → walk slots → fill .resource slots from
       │     │          the named index lookup (e.g. GrammarHelpIndex.searchByTerm)
       │     │          ↓ InteractionResult (one section per slot, template order)  → AUTO-FILL
       │     └ FALLBACK definitionID == nil → ResourceSectionIndex + HeadingFuzzyMatcher
       │                ↓ InteractionResult (ranked single-section candidates)      → user picks
       │
       ├─ ContentInserter.insertTemplate(...)  (auto-fill: all slots as a block)
       │   or InteractionPopupMenu (fallback pick / per-slot alternates submenu)
       │         ↓ (newText, range)
       └─ host writes into NSTextView / WKWebView
```

## Source Files

| File | Responsibility |
|---|---|
| `Sources/9.8 Interaction/SpecialElementDetector.swift` | `@MainActor SpecialElementDetector: SpecialElementDetecting` — two-signal detect (syntax + heading) then registry resolution → `definitionID` |
| `Sources/9.8 Interaction/SpecialElementRegistry.swift` | `actor SpecialElementRegistry` — loads `special_elements.json`; `resolve(syntaxTerm:contextHeading:)` + `definition(id:)` |
| `9.8 Interaction/special_elements.json` | Authored registry: per-element triggers + slots (bundled via `Bundle.module`) |
| `Sources/9.8 Interaction/InteractionProvider.swift` | `actor InteractionProvider` — PRIMARY registry auto-fill (walk slots, fill from index lookups); FALLBACK fuzzy ranking |
| `Sources/9.8 Interaction/ResourceSectionIndex.swift` | `actor ResourceSectionIndex` (fallback infra) — flattens topics into heading-keyed `ResourceSection`s |
| `Sources/9.8 Interaction/HeadingFuzzyMatcher.swift` | Deterministic fuzzy scorer (fallback infra) — token overlap + substring + Levenshtein |
| `Sources/9.8 Interaction/InteractionCoordinator.swift` | `@MainActor InteractionCoordinator` — orchestrates detect → lookup → auto-fill insert (or fallback popup) |
| `Sources/9.8 Interaction/InteractionPopupMenu.swift` | `InteractionPopupMenu` — `NSMenu` for the fallback pick list and per-slot alternates submenu |
| `Sources/9.8 Interaction/ContentInserter.swift` | `ContentInserter` — `insertTemplate` (all slots) + `insert` (single fallback section) |

## Foundation Types (new, in 2.7)

| Type | Purpose |
|---|---|
| `SpecialElement` / `SpecialElementKind` | The detected element: `kind` (container), `definitionID` (semantic), `syntaxTerm`, `contextHeading`, ranges |
| `SpecialElementDefinition` (+ `ElementTriggers`, `ElementSlot`, `SlotSource`, `ResourceLookup`) | A registry entry: trigger terms + ordered slots, each `userContent` or `resource(lookup:)` |
| `SpecialElementDetecting` | Protocol seam so the precedence helper can run detection without importing module 9 |
| `InteractionQuery` | Carries selected text, full document text, cursor offset, file mode, and the detected `SpecialElement` |
| `InteractionResult` / `InteractionSectionItem` | Sections (one per slot, or ranked candidates): `(sectionTitle, preview, content, resourceLanguage, matchScore)` |
| `InteractionProviding` / `InteractionInserting` | Protocols for the lookup and insertion seams |
| `SelectionContextMenu` | Foundation helper encoding the Interaction-replaces-More-Context precedence in one place |

## Special Elements

Detection requires **Signal 1 (syntax term)** to fire; **Signal 2 (contextHeading)** — the nearest heading above the selection — is then captured to bias the lookup (it refines ranking but is not required to recognise the element).

| Kind | File modes | Syntax term (Signal 1) | Insertion point |
|---|---|---|---|
| `markdownTableRow` | MD | Selection on a `\| … \|` pipe-delimited line (≥2 pipes, adjacent row also piped) | New row directly below |
| `htmlTableRow` | HTML, TXT | Selection between `<tr>` … `</tr>` | New `<tr>` directly below |
| `asciiTableRow` | ASCII, TXT | Selection on a `\|`-fenced row in an ASCII grid | New row directly below |
| `markdownBlockquote` | MD | Selection on `> …` lines | Content appended after the block |
| `htmlListItem` | HTML | Selection inside `<li>` … `</li>` | New `<li>` below |
| `fencedCodeBlock` | MD, TXT | Selection inside ` ``` ` … ` ``` ` | Content inserted as comment after closing fence |
| `htmlCodeBlock` | HTML | Selection inside `<pre><code>` | Comment/example inserted after `</pre>` |
| `asciiBoxRegion` | ASCII | Selection inside a box-drawing rectangle | Content appended inside box |

## Resource Lookup (registry-driven, with fuzzy fallback)

The provider does **not** do a flat `index.search(selectedText)`. Two paths:

**Primary — registered element (`definitionID != nil`):** look up the `SpecialElementDefinition`, walk its `slots` in order, and for each `resource(lookup:)` slot run the named `ResourceLookup` against the definition's `resourceLanguage` index, keyed by the user's selection. Each slot becomes one `InteractionResult` section, in template order. `userContent` slots emit an empty placeholder. The whole template is auto-inserted; a slot with strong alternates offers a submenu.

`ResourceLookup` → existing index call:

| `lookup` | Resource call (reused) |
|---|---|
| `lexicalDefinition` | `GrammarHelpIndex.searchByTerm(selection, preferStructural: false)` |
| `structuralAnalysis` | `GrammarHelpIndex.searchByTerm(selection, preferStructural: true)` + `GrammarSelectionAnalyzer` |
| `markdownTopic` / `htmlTopic` / `asciiTopic` | the respective index `search(selection)` best match |

Worked example — `sentence-parser` (container `markdownTableRow`, language `grammar`):

| Slot | Source | Filled by |
|---|---|---|
| `sentence` | `userContent` | left empty for the user |
| `lexical` | `resource(.lexicalDefinition)` | top Grammar lexical topic for the selected sentence/word |
| `structural` | `resource(.structuralAnalysis)` | top Grammar structural topic for the selection |

**Fallback — generic element (`definitionID == nil`):** pick the base resource from `kind`, build a weighted query (`contextHeading` + `syntaxTerm` + `selectedText`), and fuzzy-match it via `HeadingFuzzyMatcher` against `ResourceSectionIndex` headings — topic titles for every resource plus `##`/`###` body sub-headings (Grammar 49/50, Markdown 11/11; HTML/ASCII use title + `searchTerms`). Returns up to 8 ranked single-section candidates for the user to pick one.

## Technical Summary

- **Framework(s):** AppKit, Foundation, NaturalLanguage (for sentence/word boundary detection)
- **Threading:** `SpecialElementDetector` is `@MainActor` (reads `NSTextView` selection synchronously); `ResourceSectionIndex` and `InteractionProvider` are actors (async heading extraction + fuzzy ranking off the main thread); `ContentInserter` is `@MainActor` (writes to `NSTextView`)
- **Precedence:** the `SelectionContextMenu` Foundation helper runs the detector first; a detected element (with Interaction enabled) shows "Interact with…" **instead of** the More-Context items — the two never coexist on a menu
- **Activation:** `isInteractionAvailable` (Bool, `@MainActor`) is set by the coordinator on selection-change; Edit menu "Interact with" item (⌘I) and right-click item observe it
- **Toggle:** per-language flags stored in `WritingAssistMatrix.interaction` (new `.interaction` function axis added to Foundation 2.3)
- **Lookup:** registry-driven — a resolved `SpecialElementDefinition` walks its slots and fills each `resource` slot via the named index lookup (reusing `searchByTerm(_:preferStructural:)` etc.); fuzzy `HeadingFuzzyMatcher` is the fallback for unregistered elements only (deterministic, no NLEmbedding)
- **Popup:** `NSMenu` presented via `NSMenu.popUpContextMenu(_:with:for:)` at the selection or button origin; menu items carry resource section closures
- **Insertion:** `ContentInserter` determines line/range of the element's insertion point, then calls `NSTextView.insertText(_:replacementRange:)` (undo-safe) or evaluates JS in WKWebView for HTML preview

## Invariants

- `InteractionCoordinator` never imports module 3, 4, or 8 directly — it communicates via protocols owned by Foundation (SR-1)
- `ContentInserter` only writes via `NSTextView.insertText(_:replacementRange:)` or JS injection — never direct `string.insert` on the model
- Detection (Signal 1) always runs before resource lookup — a `nil` `SpecialElement` means no popup, the menu item is disabled, and More-Context appears instead
- `kind` (container) and `definitionID` (semantic) are orthogonal — one container can host many registry definitions; the registry, not the `kind`, decides what content fills the element
- A registered element auto-fills every `resource` slot from its index lookup; only a slot with genuine alternates shows a pick UI. Fuzzy ranking is used **only** when no registry definition matches
- `contextHeading` (Signal 2) refines registry resolution but is never required — a syntax term that hits a generic container definition is enough to recognise an element
- Interaction and More-Context are mutually exclusive on the right-click menu (enforced once in `SelectionContextMenu`, not per-host)
- Per-language `.interaction` toggle is checked before detection begins — disabling Grammar Interaction skips grammar detection entirely
- A resource slot whose lookup returns nothing is omitted from the inserted template — never an empty/garbage row (SR-2)
- Fallback lookup uses lightweight fuzzy matching only; `LocalSemanticSearch`/NLEmbedding is intentionally excluded from the inline path (SR-3/SR-4)
- The module owns no `AppState` state directly — it reads `AppState.activeDocument` and writes via the editor's command handler protocol (SR-1)
