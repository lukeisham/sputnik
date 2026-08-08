---
plan: More details external search links
module: 9 Resources (SputnikHelpPanel — shared across 9.2–9.5)
created: 2026-06-15
status: pending
related_issues: none
---

## Purpose
Add a "More details:" section to every help-panel topic that offers one or two bullet-point links which launch a targeted Google search about the topic in the user's default browser.

## Success Condition
- Opening any help topic (Grammar, Markdown, HTML, JSON, ASCII) shows a "More details:" heading below the topic body with 1–2 bullet links.
- Each link's label reads like a search (e.g. "Search the web for 'Subject and Predicate' grammar") and, when clicked, opens the default browser to the corresponding Google results page in a new tab.
- The query is auto-generated from the topic (title + a per-kind context word, e.g. "grammar", "markdown syntax", "HTML", "JSON", "ASCII art") — no hand-entered data.
- If no browser is available / the open fails, nothing crashes and no error dialog is thrown (SR-2); the link simply does nothing.
- The links render for all five help kinds because the section lives in the shared `SputnikHelpPanel`, not in any one content view.
- New Swift Testing cases cover URL construction (correct Google endpoint, percent-encoded query, expected per-kind context word) for representative topics.

## Success Condition — visual placement
```
  Subject and Predicate
  sentence-structure
  ──────────────────────────────
  <topic body …>
  ──────────────────────────────
  Related topics: …            (existing)
  ──────────────────────────────
  More details:                (NEW)
    • Search the web for "Subject and Predicate" grammar
    • Search the web for sentence subject vs predicate examples
```

## Steps

1. **Define the external-search link model**
   What: Add a small `Sendable` value type (e.g. `HelpExternalSearch { label: String; url: URL }`) in its own file under `9 Resources/Sources/` (SR-6).
   Why: Gives the view a typed, testable list to render instead of building strings inline.

2. **Build the query/URL generator**
   What: Add a `HelpExternalSearchBuilder` (own file) with a static func that takes a topic `title`, its `searchTerms`, and the panel's `helpKind`, and returns 1–2 `HelpExternalSearch` values. Map `helpKind` → a context word (`.grammar`→"grammar", `.markdown`→"markdown syntax", `.html`→"HTML", `.json`→"JSON", `.asciiArt`→"ASCII art", `.sputnik`→""). Construct `https://www.google.com/search?q=<percent-encoded query>` using `URLComponents`/`URLQueryItem` so encoding is correct. Link 1 = `"<title>" <contextWord>`; link 2 (only when a distinct `searchTerm` exists) = a second phrasing from the top search term. Return `[]` if no valid URL can be formed.
   Why: Centralises query logic in one pure, testable function; `URLComponents` guarantees safe encoding (SR-2). Auto-generation was the chosen approach — zero data entry, every topic covered.

3. **Render the "More details:" section in the shared panel**
   What: In `SputnikHelpPanel.contentArea`, after the existing Related-topics section, add a `moreDetailsSection(topic)` that calls the builder with `topic` + `helpKind` and renders the heading "More details:" plus one bullet per `HelpExternalSearch`. Use SwiftUI's `Link(destination:)` (or `@Environment(\.openURL)`) so the OS opens the default browser and gracefully no-ops when unavailable. Hide the whole section when the builder returns `[]`. Style with existing `SputnikColor`/`SputnikFont`/`SputnikSpacing` tokens to match `relatedTopicsSection`.
   Why: One change in the shared panel covers all five help kinds (the chosen scope). `Link`/`openURL` is the SwiftUI-first way to open a browser (SW-3) and handles the "if accessible" case without manual error handling.

4. **Match existing section styling**
   What: Give "More details:" the same `Divider()` + heading + indented-bullet treatment the Related-topics section uses, so it reads as a peer section.
   Why: Visual consistency; reuses Foundation UI tokens (SR-1) rather than inventing new styling.

5. **Write Swift Testing coverage**
   What: Add tests under `9 Resources/Tests/` asserting: the builder returns a Google `https://www.google.com/search` URL; the query is percent-encoded and contains the title; the per-kind context word is correct for grammar/markdown/html/json/asciiArt; an empty/edge topic yields `[]` (no crash); at most two links are returned.
   Why: Locks URL correctness and the per-kind mapping so future edits can't silently break the links.

6. **Update Module Guides**
   What: In `9 Resources/.../9.5 Grammar Help/guide.md` (and a brief note where the shared panel is documented), record the new "More details:" section, the builder, and that it applies to all help kinds via `SputnikHelpPanel`. Bump `last_updated`/`last_verified`.
   Why: Keep the guide aligned with the code after the change (working conventions).

## Risks and Constraints
- **Browser availability (SR-2):** Opening may fail (no default browser, sandbox restriction). Using SwiftUI `Link`/`openURL` means the failure is a silent no-op — verify no force-unwrap on `URL` (use `URLComponents.url` optionally, drop the link if nil).
- **Query quality:** Auto-generated queries can be generic. Accepted by the chosen approach; the per-kind context word keeps them targeted, and a curated field can be added later if needed.
- **Shared-panel blast radius:** The change touches `SputnikHelpPanel`, used by all four help panels. It is additive (a new optional section) and renders nothing when the builder returns `[]`, so existing panels are unaffected.
- **No Foundation change:** URL building and opening stay inside module 9's view/util — no new Foundation type required, so this does not widen the cross-module surface (SR-1).
- **No new dependencies (SR-5):** Uses `Foundation.URLComponents` and SwiftUI only.

## Files Affected
- `9 Resources/Sources/HelpExternalSearch.swift` — new: link value type.
- `9 Resources/Sources/HelpExternalSearchBuilder.swift` — new: per-kind Google query/URL generator.
- `9 Resources/Sources/SputnikHelpPanel.swift` — render the "More details:" section in `contentArea`.
- `9 Resources/Tests/` — new Swift Testing cases for URL construction.
- `1 Setup/Module Guides/9 Resources/9.5 Grammar Help/guide.md` — document the new section.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[9 Resources] More details external search links`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
