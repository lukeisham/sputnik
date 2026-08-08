# Plan: Syntax Highlighting Inside Fenced Code Blocks

> **Created:** 2026-06-12
> **Status:** ready
> **Feature:** Future Features #1 — Syntax highlighting inside fenced code blocks
> **Modules touched:** 3.1 (Text Editor / SyntaxHighlighter), 2.3 (Settings)
> **Estimated effort:** 2–3 days
> **Risk:** Low — extends an existing, well-architected pipeline; no new infrastructure needed

---

## Scope: Markdown only

This plan covers **one editing mode** — `.markdown`. When the user writes a fenced code block with a language tag, the content inside the fence gets language-specific token coloring.

| Fence tag | Action |
|---|---|
| ` ```swift ` | Apply Swift tokenizer (keywords blue, strings red, comments gray, etc.) |
| ` ```html ` | Delegate to existing `htmlAttributes(in:)` (tags blue, attributes orange, comments gray) |
| ` ``` ` (no tag) | Plain monospace — no color |
| Anything else | Plain monospace — graceful fallback, no crash |

HTML-mode editing (`.html`) already has its own colorizer (`htmlAttributes(in:)`) which handles tags, attributes, and comments. No change to that path.

---

## Approach

The existing `SyntaxHighlighter.markdownAttributes(in:)` already matches fenced code blocks with a blunt regex and colors them all one flat green:

```swift
(#"```[\s\S]*?```"#, .systemGreen),  // Fenced code
```

The plan extends this to:
1. **Extract the language tag** from the opening fence (` ```swift ` → `swift`)
2. **Tokenize Swift code** with keyword/string/comment/number rules
3. **Apply per-token colors** — blue for keywords, red for strings, gray for comments, teal for attributes
4. **Cache tokenized results** by block range to avoid re-tokenizing on every keystroke
5. **Gate behind a Settings toggle** for distraction-free writing

No new files outside `SyntaxHighlighter.swift` (plus a settings toggle). The existing scoped re-highlighting (`expandedRange()` with ±5 line look-behind) already limits the performance impact.

---

## Step-by-Step

### Step 1 — Add helper: parse fenced code blocks from Markdown text

**File:** `3 Text Editor/3.1 Text/SyntaxHighlighter.swift`

Add a private method that extracts all fenced code blocks from Markdown source:

```swift
/// Returns (range, languageTag) for each fenced code block in the Markdown text.
/// Language tag is lowercase, trimmed; nil when no tag follows the opening ```.
private func fencedCodeBlocks(in text: String, baseOffset: Int = 0) -> [(NSRange, String?)]
```

**Implementation:** Scan for lines matching `^```(\S*)$` (opening fence), then find the matching closing ` ``` ` line. Collect the range between the fences and the optional language word.

**Edge cases:**
- ` ``` ` with no language tag → plain monospace, skip tokenization
- ` ```swift  ` → trim whitespace from tag
- Nested/non-matching fences → skip
- Tildes (`~~~`) as an alternative fence delimiter

**Risk:** Low. Regex-based block detection is well-understood.

---

### Step 2 — Add Swift tokenizer

**File:** `3 Text Editor/3.1 Text/SyntaxHighlighter.swift`

A static method that takes a code string and returns `[(NSRange, NSColor)]`. Runs on `Task(priority: .utility)` (SR-4).

```swift
private static func swiftTokenAttributes(in text: String) -> [(NSRange, NSColor)]
```

| Token type | Pattern / Rule | Color |
|---|---|---|
| Line comment | `//...` | `.systemGray` |
| Block comment | `/* ... */` | `.systemGray` |
| String literal | `"..."` (single-line, handle `\"` escapes) | `.systemRed` |
| Multi-line string | `"""..."""` | `.systemRed` |
| Raw string | `#"..."#` | `.systemRed` |
| Keyword | `let`, `var`, `func`, `class`, `struct`, `enum`, `protocol`, `extension`, `import`, `if`, `else`, `guard`, `for`, `while`, `switch`, `case`, `return`, `throw`, `throws`, `async`, `await`, `try`, `catch`, `do`, `repeat`, `in`, `where`, `self`, `Self`, `super`, `true`, `false`, `nil`, `public`, `private`, `internal`, `fileprivate`, `open`, `static`, `final`, `mutating`, `nonmutating`, `override`, `required`, `convenience`, `weak`, `unowned`, `lazy`, `init`, `deinit`, `subscript`, `associatedtype`, `typealias`, `precedencegroup`, `infix`, `prefix`, `postfix`, `operator`, `get`, `set`, `willSet`, `didSet`, `some`, `any`, `actor`, `isolated`, `nonisolated`, `Task`, `MainActor`, `Sendable`, `Observable`, `Codable`, `Equatable`, `Hashable`, `Identifiable`, `CaseIterable`, `String`, `Int`, `Double`, `Bool`, `Array`, `Dictionary`, `Set`, `Optional`, `Result`, `throws`, `rethrows`, `continue`, `break`, `fallthrough`, `default` | `.systemBlue` |
| Type annotation keywords | `:`, `->`, `as`, `is` (when used as type operators) | `.systemPurple` |
| Number literal | `\b\d+(\.\d+)?\b` | `.systemOrange` |
| Declaration attribute | `@[a-zA-Z]+` (e.g. `@MainActor`, `@Observable`) | `.systemTeal` |

#### Language: HTML (already handled)

For ` ```html ` fenced blocks: delegate to the existing `htmlAttributes(in:)` — it already colors tags, attributes, and comments. No new tokenizer needed.

#### Language: Unknown / plain

No special coloring — plain monospace. The flat-green fallback is removed.

---

### Step 3 — Integrate into `markdownAttributes(in:)`

**File:** `3 Text Editor/3.1 Text/SyntaxHighlighter.swift`

Modify `markdownAttributes(in:)`:

1. Keep the existing regex patterns for headings, bold, italic, inline code, links — these color content *outside* fenced blocks
2. For the fenced-code regex (`#"\`\`\`[\s\S]*?\`\`\`"#`), **remove** the flat-green coloring
3. Call the new `fencedCodeBlocks(in:)` helper to find all fenced blocks
4. For each block, dispatch:
   - `"swift"` → `swiftTokenAttributes(in:)`
   - `"html"` → `htmlAttributes(in:)` (existing)
   - Anything else → `[]` (plain monospace)
5. Merge tokenized attributes into the result array

**Order of precedence:** Fenced code blocks take priority. Process blocks first, then apply outer-Markdown patterns only to ranges outside the blocks.

```
result = tokenizedCodeBlockAttributes  // step 1: color code blocks
       + markdownPatternAttributes     // step 2: color headings, bold, etc. (outside blocks)
```

**Risk:** Medium. The merge logic needs to prevent double-coloring (e.g. a `*` inside a code block should NOT be colored as italic). After collecting all fenced block ranges, skip any outer-Markdown pattern match that intersects a code block range.

---

### Step 4 — Performance: cache tokenized results

**File:** `3 Text Editor/3.1 Text/SyntaxHighlighter.swift`

Add a simple cache to `SyntaxHighlighter`:

```swift
/// Cache keyed by startLocation → avoiding full re-tokenization.
private var codeBlockCache: [Int: [(NSRange, NSColor)]] = [:]
```

- Key = the opening fence's character location (stable across edits within the block)
- Invalidate cache entries whose range intersects the `editedRange`
- On invalidation, re-tokenize only the affected blocks

The existing `expandedRange()` already scopes the work area to ±5 lines around the edit. The cache ensures a keystroke inside a 200-line code block only re-tokenizes that one block.

**Cache invalidation:**
- After text changes: remove cache entries whose range overlaps `editedRange`
- On mode change: clear entire cache

**Risk:** Low. Straightforward caching pattern.

---

### Step 5 — Add Settings toggle

**File:** `2 Foundation/2.3 Settings/SettingsStore.swift`

- Add `public var codeBlockHighlightEnabled: Bool = true`
- Add persistence key `"sputnik.settings.codeBlockHighlight"`
- Add `setCodeBlockHighlightEnabled(_:)` mutator

**File:** `2 Foundation/2.5 Persistence/SettingsLoader.swift`

- Add load/write for the new key

**File:** `App-Sputnik/EditorTab.swift`

- Add toggle in settings UI

When disabled, fenced code blocks render as plain monospace (no color).

**Risk:** None. Identical pattern to the 20+ existing boolean toggles.

---

### Step 6 — Pass the toggle into `SyntaxHighlighter`

**File:** `3 Text Editor/3.1 Text/SyntaxHighlighter.swift`

- Add `public var codeBlockHighlightEnabled: Bool = true` property
- In `markdownAttributes(in:)`, when `false`, skip code-block parsing entirely (keep only existing Markdown patterns)

**File:** `3 Text Editor/3.1 Text/EditorView.swift`

- In the coordinator, propagate `settings.codeBlockHighlightEnabled` to the syntax highlighter

**Risk:** None. A single boolean propagation.

---

### Step 7 — Tests

**File (new):** `3 Text Editor/Tests/SyntaxHighlighterCodeBlockTests.swift`

| Test | What it verifies |
|---|---|
| `swiftKeywordIsBlue` | `let x = 1` inside ` ```swift ` → `let` is `.systemBlue` |
| `swiftCommentIsGray` | `// comment` inside ` ```swift ` → gray |
| `swiftStringIsRed` | `"hello"` inside ` ```swift ` → `.systemRed` |
| `swiftAttributeIsTeal` | `@MainActor` inside ` ```swift ` → `.systemTeal` |
| `htmlFencedBlockColored` | ` ```html ` → delegate to `htmlAttributes(in:)` → tags blue, attributes orange |
| `unknownLanguageFallsBackToMonospace` | ` ```python ` → plain text, no crash |
| `noLanguageTagIsPlain` | ` ``` ` with no tag → plain monospace |
| `markdownPatternsIgnoredInsideFence` | `*bold*` inside ` ```swift ` → NOT italic-colored |
| `headingsOutsideFenceStillColored` | `# Heading` before/after a fenced block → still blue |
| `nestedBackticksAreNotFences` | ` `` ` inside a fenced block → not treated as a fence |
| `tildeFenceDetected` | `~~~swift\nlet x = 1\n~~~` → same as backtick fence |
| `toggleOffDisablesHighlighting` | `codeBlockHighlightEnabled = false` → all blocks plain monospace |
| `cacheInvalidatedOnEdit` | Edit inside a block → only that block re-tokenized |
| `cachePreservedOnEditOutsideBlock` | Edit outside all blocks → code block cache untouched |
| `largeBlockDoesntTimeout` | 500-line code block → highlight completes in <100ms |

---

## Files Summary

| File | Action | Lines (est.) |
|---|---|---|
| `3.1/SyntaxHighlighter.swift` | Add fenced-block parser + Swift tokenizer + cache + toggle gate | ~250 |
| `2.3/SettingsStore.swift` | Add toggle + persistence key + mutator | +20 |
| `2.5/SettingsLoader.swift` | Load/write new key | +10 |
| `3.1/EditorView.swift` | Propagate toggle to highlighter | +5 |
| `App-Sputnik/EditorTab.swift` | Settings toggle UI | +5 |
| `3/Tests/SyntaxHighlighterCodeBlockTests.swift` | **New** — unit tests | ~150 |
| **Total** | | **~440 lines** |

---

## Invariants

1. **Tokenization never runs on the main thread** — all `Task(priority: .utility)` (SR-4)
2. **Unknown languages degrade gracefully** — no crash on ` ```python `; just plain monospace
3. **Markdown syntax inside fenced blocks is NEVER colored** — `*` inside ` ```swift ` is just a character, not italic
4. **The toggle defaults to `true`** — this is a visible differentiator
5. **The cache key is the opening fence location** — stable across intra-block edits

---

## Performance Budget

| Scenario | Target |
|---|---|
| 100-line Markdown, single 20-line Swift block | <5ms per highlight pass |
| 1000-line Markdown, three 100-line code blocks | <50ms per highlight pass (initial), <5ms (cached) |
| Keystroke inside a 500-line code block | <10ms (scoped re-highlight + cache hit on other blocks) |

---

## Verification Checklist

- [ ] Build compiles
- [ ] Unit tests pass (`swift test --filter SyntaxHighlighterCodeBlockTests`)
- [ ] Open a Markdown file with a ` ```swift ` block — keywords are blue, strings are red, comments are gray, attributes are teal
- [ ] Open a Markdown file with a ` ```html ` block — HTML tags/attributes colored correctly (delegates to existing)
- [ ] ` ``` ` with no language tag → plain monospace, no crash
- [ ] ` ```python ` → plain monospace, no crash
- [ ] Toggle off in Settings — all blocks revert to plain monospace
- [ ] Edit inside a long code block — typing is responsive
- [ ] Markdown syntax outside blocks still colored correctly
- [ ] Markdown syntax inside blocks NOT colored (no italic inside code)
