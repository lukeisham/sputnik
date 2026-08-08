# Plan: Lightweight HTML Syntax Checking

> **Created:** 2026-06-12
> **Status:** ready
> **Feature:** Future Features #2 — HTML Error Checking (cheeky lightweight approach)
> **Modules touched:** 3.4 (HTML Language), 3.5 (Spelling & Grammar), 3.1 (Text Editor), 2.3 (Settings), App-Sputnik (Settings UI)
> **Estimated effort:** 2–3 days
> **Risk:** Low — clones an existing, battle-tested pipeline

---

## Approach

Instead of building a new diagnostic infrastructure from scratch (inline underlines, issues sidebar, custom parser), clone the existing `SpellingGrammarChecker` pattern:

1. **Structural scan** — regex-based, inspired by the structural awareness already in `HTMLLanguageProvider.suggest(in:)`, applied to the full document
2. **Annotation model** — reuse `GrammarAnnotation` (add `.htmlSyntax` kind), exact same `range` + `suggestions` + `isSuppressed` shape
3. **Rendering** — reuse the spell/grammar underline pipeline: write `.underlineStyle` + `.underlineColor` directly to `NSTextStorage`. No custom AppKit drawing.
4. **Debounce** — same `DebounceTimer` pattern, same 0.5s quiet period as spelling
5. **Wiring** — same coordinator pattern as `SpellingGrammarChecker` in `EditorView.makeNSView`

**Why this works:** The `SpellingGrammarChecker` already proves the full pipeline — debounce → scan → annotate → underline → dismiss — works reliably on `NSTextStorage`. We swap `NSSpellChecker.check(...)` for a 50-line regex scan and change the underline color from red/orange to blue.

---

## Step-by-Step

### Step 1 — Extend `GrammarAnnotation.Kind` with `.htmlSyntax`

**File:** `3 Text Editor/3.5 Spelling and Grammar Checking/GrammarAnnotation.swift`

- Add `case htmlSyntax` to the `Kind` enum
- No other changes — the `range`, `suggestions`, `isSuppressed` fields already fit the shape

**Risk:** None. Adding a case to an existing enum with no default branches means the compiler will flag every `switch` that needs updating. The checker's `runCheck()` method switches on kind for underline color — add blue for `.htmlSyntax`.

**Verification:** Existing tests pass; `GrammarAnnotation(range:kind:.htmlSyntax,suggestions:["fix"])` compiles and roundtrips through Equatable.

---

### Step 2 — Add `htmlSyntaxCheckEnabled` toggle to `SettingsStore`

**File:** `2 Foundation/2.3 Settings/SettingsStore.swift`

- Add `public var htmlSyntaxCheckEnabled: Bool = true`
- Add persistence key `"sputnik.settings.htmlSyntaxCheck"`
- Add `setHtmlSyntaxCheckEnabled(_:)` mutator
- Default `true` — it's a helpful feature, not an intrusive one

**File:** `2 Foundation/2.5 Persistence/SettingsLoader.swift`

- Add load/write for the new key, following the existing pattern

**Risk:** None. The settings store already has 20+ boolean toggles with identical patterns. Pure copy-paste-rename.

---

### Step 3 — Create `HTMLSyntaxChecker`

**File (new):** `3 Text Editor/3.4 HTML Langugage/HTMLSyntaxChecker.swift`

Pattern: clone of `SpellingGrammarChecker`, stripped down. Key differences:

| Aspect | SpellingGrammarChecker | HTMLSyntaxChecker |
|---|---|---|
| Scan engine | `NSSpellChecker.check(...)` | Regex-based structural scan (see below) |
| Active gate | `viewModel.spellCheckActive` | `viewModel.htmlModeActive` + `settings.htmlSyntaxCheckEnabled` |
| Annotations returned | `.spelling`, `.grammar` | `.htmlSyntax` only |
| Underline color | Red (spelling), orange (grammar) | Blue (`.systemBlue`) or yellow (`.systemYellow`) |
| Dismissal | `NSSpellChecker.ignoreWord` / local set | Local `ignoredHTMLRanges: Set<NSRange>` for session-only |
| Instant Correct | Supported | Not supported (no single-word corrections for structure) |
| Spelling-over-grammar suppression | Yes | No direct equivalent, but HTML underlines should be suppressed by spelling underlines (same logic: if a spelling error overlaps, show red not blue) |

**Public interface:**

```swift
@MainActor
public final class HTMLSyntaxChecker {
    public init(textView: NSTextView, viewModel: EditorViewModel, settings: SettingsStore)
    public func onTextChange()              // debounced trigger
    public func annotation(at: Int) -> GrammarAnnotation?  // hit-test
    public func dismiss(_: GrammarAnnotation)              // ignore for session
    public private(set) var annotations: [GrammarAnnotation]
}
```

**Structural scan method:**

Offload to `Task(priority: .utility)` (SR-4). Three checks, applied as regex passes over the full `textStorage.string`:

1. **Unclosed tags** — Walk the string, maintaining a stack of open tag names. When `</name>` is encountered, pop the stack. If the closing tag doesn't match the stack top → flag it. At end of string, any tags left on the stack → flag their open position.
   - Supported block tags: `div`, `p`, `span`, `ul`, `ol`, `li`, `table`, `tr`, `td`, `th`, `section`, `article`, `header`, `footer`, `nav`, `main`, `aside`, `h1`–`h6`, `form`, `fieldset`, `body`, `head`, `html`
   - Void elements (`br`, `hr`, `img`, `input`, `meta`, `link`) are excluded from the stack

2. **Unquoted attribute values with spaces** — Regex: `\s[a-zA-Z-]+=([^"'][^\s>]+)` — catches `class=foo bar` where `bar` would be parsed as a separate attribute

3. **Duplicate `id` attributes** — Collect all `id="value"` strings, flag duplicates beyond the first

Returns `[GrammarAnnotation]` with `.htmlSyntax` kind and descriptive suggestion strings (e.g. `"Unclosed <div>"`, `"Mismatched tag: expected </span>"`).

**Suppression priority:** After building HTML annotations, check for overlap with spelling annotations (from `SpellingGrammarChecker.annotations`). Suppress any HTML annotation whose range overlaps a spelling range.

**Risk:** The tag-stack walk needs to handle nested same-name tags correctly (e.g. `<div><div></div></div>`). The void-elements list must be comprehensive. Both are well-understood problems.

---

### Step 4 — Wire `HTMLSyntaxChecker` into `EditorView` coordinator

**File:** `3 Text Editor/3.1 Text/EditorView.swift`

In `makeNSView`:
- Create `HTMLSyntaxChecker` instance after the spelling checker
- Store in coordinator as a strong reference (same as `checker`)

In `textDidChange`:
- Add `htmlSyntaxChecker?.onTextChange()` call, gated on `viewModel.htmlModeActive == true`

**File:** `3 Text Editor/3.1 Text/EditorTextView.swift`

- Add `weak var htmlSyntaxChecker: HTMLSyntaxChecker?` (same pattern as `spellingChecker`)
- In the click-hit-testing method, check `htmlSyntaxChecker.annotation(at:)` as a fallback when spelling checker returns nil

**Risk:** Low. The coordinator already holds 6+ long-lived references to providers/checkers. Adding one more follows the exact same pattern. No new retain cycle risk (all are one-way: coordinator → checker, text view has weak refs).

---

### Step 5 — Add underline color for `.htmlSyntax` in `SpellingGrammarChecker`

**File:** `3 Text Editor/3.5 Spelling and Grammar Checking/SpellingGrammarChecker.swift`

In `runCheck()`, the color switch already branches on `.spelling` (red) vs `.grammar` (orange). On the *reading* side: when `SpellingGrammarChecker` writes underlines, it currently only writes its own annotations. No change needed — `HTMLSyntaxChecker` will write its own underlines.

However, the **spelling-overlap suppression** logic currently lives inside `SpellingGrammarChecker.runCheck()`. The HTML checker needs to query the spelling checker's annotations to suppress HTML underlines that overlap spelling errors. Add a public read-only accessor: `SpellingGrammarChecker.spellingRanges` (or simply read `.annotations` which is already `public private(set)`).

Actually, simpler: `annotations` is already public. The HTML checker can read `spellingChecker.annotations`, filter to `.spelling` kind with `!isSuppressed`, and suppress any of its own annotations that overlap.

**Risk:** Low. No structural changes to `SpellingGrammarChecker`. Just reading an already-public property.

---

### Step 6 — Add toggle to Settings UI

**File:** `App-Sputnik/SettingsView.swift` (or a relevant tab)

Option A: Add to the existing `EditorTab` (since HTML checking is an editor feature, not a spelling/grammar feature).

```swift
Toggle("HTML syntax checking", isOn: Binding(
    get: { settings.htmlSyntaxCheckEnabled },
    set: { settings.setHtmlSyntaxCheckEnabled($0) }
))
```

**Risk:** None. One Toggle in an existing Form.

---

### Step 7 — Tests

**File (new):** `3 Text Editor/Tests/HTMLSyntaxCheckerTests.swift`

Following the pattern of `SpellingGrammarCheckerTests` (if they exist — check `TextEditorModuleTests.swift`). Test suite:

| Test | What it verifies |
|---|---|
| `unclosedDivTagProducesAnnotation` | `<div>text` → one `.htmlSyntax` annotation on `<div>` |
| `properlyClosedDivProducesNoAnnotation` | `<div>text</div>` → zero annotations |
| `mismatchedClosingTagProducesAnnotation` | `<span><div>text</span></div>` → annotation on the first mismatch |
| `voidElementsDontNeedClosing` | `<br>` and `<img src="x">` → zero annotations |
| `nestedSameTagsAreValid` | `<div><div></div></div>` → zero annotations |
| `unquotedAttributeProducesAnnotation` | `<div class=foo bar>` → annotation on the attribute |
| `duplicateIdProducesAnnotation` | Two `id="main"` → annotation on the second |
| `nonHtmlModeProducesNoAnnotations` | `htmlModeActive == false` → `onTextChange()` no-ops |
| `disabledViaSettingsProducesNoAnnotations` | `htmlSyntaxCheckEnabled == false` → no scan |
| `dismissRemovesAnnotationThisSession` | Dismiss an annotation → re-check excludes it |
| `spellingOverlapSuppressesHtmlAnnotation` | Spelling error on same range → HTML annotation is suppressed |
| `htmlAnnotationsClearedOnModeChange` | Switch to `.plainText` → annotations cleared |
| `emptyDocumentProducesNoAnnotations` | Empty string → zero annotations |

**Risk:** Low. The test patterns are well-established for the spelling checker. `NSTextView` + `NSTextStorage` setup is identical.

---

## Files Summary

| File | Action | Lines (est.) |
|---|---|---|
| `3.5/GrammarAnnotation.swift` | Add `.htmlSyntax` case | +1 |
| `2.3/SettingsStore.swift` | Add toggle + persistence key + mutator | +20 |
| `2.5/SettingsLoader.swift` | Load/write new key | +10 |
| `3.4/HTMLSyntaxChecker.swift` | **New** — checker class | ~200 |
| `3.1/EditorView.swift` | Wire into coordinator | +10 |
| `3.1/EditorTextView.swift` | Add weak ref + hit-test fallback | +8 |
| `App-Sputnik/EditorTab.swift` (or similar) | Settings toggle | +5 |
| `3/Tests/HTMLSyntaxCheckerTests.swift` | **New** — unit tests | ~150 |
| **Total** | | **~400 lines** |

---

## Invariants

1. `HTMLSyntaxChecker` never writes to `AppState` — it only mutates `NSTextStorage` attributes and its own `annotations` array (SR-1)
2. All regex/string scanning runs on `Task(priority: .utility)` — main thread only writes attributes (SR-4)
3. HTML underlines use a distinct color from spelling (red) and grammar (orange) — recommend `.systemBlue`
4. An HTML annotation overlapping a spelling annotation is always suppressed (spelling takes priority)
5. `htmlSyntaxCheckEnabled` defaults to `true` — this is a helpful, low-noise feature

---

## What This Does NOT Do

- **No inline underlines from scratch** — reuses `NSTextStorage` attributes, same as spell check
- **No full HTML5 parser** — regex-based structural checks only. Catches ~80% of real-world errors.
- **No issues sidebar** — underlines only. A sidebar can be added later using the same annotation model.
- **No auto-fix** — unlike spelling (Instant Correct), structural fixes need user intent. Suggestions are displayed in the quick-fix popover (the `EditorTextView.presentQuickfix(for:)` method already handles `GrammarAnnotation` generically, so it should work for `.htmlSyntax` without changes).
- **No CSS/JS checking** — HTML structure only
- **No config file or lint rules** — opinionated checks only

---

## Verification Checklist

- [ ] Build compiles with new `.htmlSyntax` case handled in all switches
- [ ] Unit tests pass (`swift test --filter HTMLSyntaxCheckerTests`)
- [ ] Existing tests pass (regression — the `GrammarAnnotation.Kind` change is additive)
- [ ] Open an HTML file with `<div>unclosed` — blue underline appears under `<div>`
- [ ] Fix the unclosed tag — underline disappears after debounce
- [ ] Toggle off in Settings — underlines disappear immediately
- [ ] Switch to Markdown mode — HTML underlines disappear (gated on `htmlModeActive`)
- [ ] Right-click an HTML underline — quick-fix popover shows the suggestion message
