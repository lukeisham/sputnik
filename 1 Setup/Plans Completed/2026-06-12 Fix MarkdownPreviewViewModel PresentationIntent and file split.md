---
plan: Fix MarkdownPreviewViewModel — implement PresentationIntent parsing and split file
status: new
created: 2026-06-11
author: Zed (code analysis)
issues: ISS-053, ISS-054, ISS-055
---

## Summary

`MarkdownPreviewViewModel.swift` (366 lines) has three interconnected problems:

1. **ISS-053 (High):** `parseIntentKind(_:)` is a stub that always returns `nil`, so `PresentationIntent` styling — headings, code blocks, blockquotes, lists — is completely non-functional. Everything renders as plain text.

2. **ISS-054 (Medium):** Five distinct concerns are mixed in one file, violating SR-6.

3. **ISS-055 (Medium):** The `Any`-typed `parseIntentKind` signature erases compile-time safety and depends on undocumented `NSPresentationIntent` Objective-C selectors that may change across macOS releases.

## Current State

The current rendering pipeline:

```
parseMarkdownSegment(text)
  → AttributedString(markdown: text, interpretedSyntax: .full)     ← emits PresentationIntent metadata
  → applyPresentationIntentStyling(attributed)
      → for run in attributed.runs:
          → guard let intent = run.presentationIntent         ← type-erased to Any?
          → guard let kind = parseIntentKind(intent)           ← ALWAYS returns nil (stub)
      → for (range, kind) in intents:                         ← empty array, nothing applied
          → applyKindAttributes(kind, to: result, range:)     ← never reached
```

Result: the styled `NSAttributedString` is returned with zero custom attributes. `NSTextView` renders headings, code, blockquotes, and lists as plain text with no visual distinction.

The `@unchecked Sendable` on `SendableAttributedString` (line 118) is a **legitimate** workaround — `NSAttributedString` is immutable after creation but not marked `Sendable` in the SDK. This is not a bug; it is fine as-is.

## Design

### Goal 1: Implement `parseIntentKind`

The function needs to inspect the private `NSPresentationIntent` Objective-C object passed via `run.presentationIntent` and map it to a `ParsedIntentKind` value.

`NSPresentationIntent` exposes its identity through `NSSelectorFromString("identity")`, which returns an `NSPresentationIntentIdentity` enum with cases like `.header(level:)`, `.codeBlock`, `.blockQuote`, `.unorderedList`, `.orderedList`, `.listItem`, `.table`, `.tableCell`.

The implementation uses `perform(_:)` via `NSObject` since the type is not publicly bridged to Swift:

```swift
private func parseIntentKind(_ intent: Any) -> ParsedIntentKind? {
    guard let obj = intent as? NSObject else { return nil }
    let identitySel = NSSelectorFromString("identity")
    guard obj.responds(to: identitySel) else {
        // Fall back to KVC for newer/more resilient access.
        let kind = obj.value(forKey: "identity")
        // ...
        return nil
    }
    let raw = obj.perform(identitySel).takeUnretainedValue()
    // Map raw → ParsedIntentKind via known NSPresentationIntentIdentity values
    // ...
}
```

A **simpler, more maintainable alternative** avoids private selectors entirely by leveraging the `AttributedString` field values directly:

Since `AttributedString` with `.full` parsing applies semantic attributes (`.headerLevel`, `.codeBlock`, `.blockQuote`) to runs, we can inspect the `AttributedString`'s attribute values directly on the Swift side rather than poking at the ObjC `NSPresentationIntent`.

```swift
private func parseIntentKind(from attributes: some AttributedStringProtocol) -> ParsedIntentKind? {
    // Swift AttributedString applies semantic attributes when interpretedSyntax: .full
    if let headerLevel = attributes.headerLevel {
        return .header(level: Int(headerLevel))
    }
    if attributes.isCodeBlock {
        return .codeBlock
    }
    // ... etc
}
```

This is Swift API surface (not private ObjC SPI), so it's far more resilient across OS updates. **This is the recommended approach for this plan.**

### Goal 2: Split the file (SR-6)

Extract concerns into separate files:

| New file | Content | Original lines | Size estimate |
|---|---|---|---|
| `MarkdownPreviewViewModel.swift` | The `MarkdownPreviewViewModel` class only (keep as-is) | 122–245 | ~125 lines (was 366) |
| `MarkdownPreview+ParsedIntentKind.swift` | `ParsedIntentKind` enum, heading font sizes | 1–25 | ~25 lines |
| `MarkdownPreview+PresentationIntent.swift` | All rendering functions + `SendableAttributedString` | 27–120, 247–366 | ~215 lines |
| — OR merge the two helper files into — | | | |
| `MarkdownPreviewRenderer.swift` | Everything rendering-related (single helper file) | 1–25, 27–120, 247–366 | ~240 lines |

**Recommended split:** Two helper files is cleaner (SR-6). `ParsedIntentKind` is a distinct type that belongs in its own file. The rendering functions form a coherent group.

### Goal 3: Address the private-API fragility (ISS-055)

The recommended approach (inspecting Swift `AttributedString` attributes like `headerLevel` instead of calling private ObjC selectors) eliminates the private-API dependency entirely. If Swift `AttributedString` ever removes these semantic attributes, the rendering silently degrades to plain text — the same degraded state as today — but with the advantage that no private-API calls exist to crash or produce undefined behaviour.

---

## Steps

### Step 1 — Implement `parseIntentKind` via Swift AttributedString attributes

Replace the stub at lines 60–62:

```swift
/// Extracts a `ParsedIntentKind` from a Swift `AttributedString` run's semantic attributes.
///
/// Uses documented Swift `AttributedString` attribute keys (`headerLevel`, inline code
/// presentation intent, etc.) instead of calling private `NSPresentationIntent` ObjC
/// selectors (ISS-055). If a future OS version removes these attributes, rendering
/// silently degrades to plain text — no crash, no undefined behaviour.
private func parseIntentKind(from attributes: some AttributedStringProtocol) -> ParsedIntentKind? {
    // Header levels (1–6)
    if let headerLevel = attributes.headerLevel {
        return .header(level: Int(headerLevel))
    }
    
    // TODO: Map other known semantic attributes
    // - Code block: attributes.presentationIntent matches .codeBlock
    // - Block quote: attributes.presentationIntent matches .blockQuote
    // - List: attributes.presentationIntent matches .listItem / .unorderedList / .orderedList
    // - Table: attributes.presentationIntent matches .table / .tableCell
    
    return nil
}
```

Update the caller in `applyPresentationIntentStyling` (line 43–47):

```swift
for run in attributed.runs {
    guard run.presentationIntent != nil else { continue }
    guard let kind = parseIntentKind(from: run) else { continue }
    let nsRange = NSRange(run.range, in: attributed)
    intents.append((nsRange, kind))
}
```

Note: `run.presentationIntent` is still checked for a non-nil guard to avoid allocating intents for plain-text runs. The actual parsing uses the Swift-side attributes, not the intent object itself.

### Step 2 — Verify the implementation

1. Build `FoundationModule` and `MarkdownPreviewModule`.
2. Open a `.md` file containing headings, fenced code blocks, block quotes, and lists.
3. Visually confirm that the Markdown Preview panel renders them with styled attributes (bold headings, monospaced code with grey background, indented block quotes, indented list items).
4. If some attributes are still plain text, the run parsing needs adjustment — see TODOs in `parseIntentKind`.

### Step 3 — Split the file

1. Create `4 Markdown Preview/MarkdownPreview+ParsedIntentKind.swift`:
   - Move `headingFontSizes` (line 10)
   - Move `ParsedIntentKind` enum (lines 16–25)
   - Keep imports minimal (`import Foundation`)

2. Create `4 Markdown Preview/MarkdownPreviewRenderer.swift`:
   - Move `parseIntentKind` (line 60–62 → replaced with new implementation)
   - Move `applyPresentationIntentStyling` (lines 39–57)
   - Move `applyKindAttributes` (lines 66–114)
   - Move `SendableAttributedString` (lines 118–120)
   - Move `buildNSAttributedString` (lines 252–302)
   - Move `parseMarkdownSegment` (lines 306–319)
   - Move `resolveImageAttachment` (lines 327–366)
   - Add `import AppKit` for `NSAttributedString`, `NSFont`, etc.
   - Add `import ResourcesModule` for `PreviewImageResolver`, `PreviewImageCache`

3. Update `MarkdownPreviewViewModel.swift`:
   - Remove all moved code
   - Keep just the `MarkdownPreviewViewModel` class (lines 122–245)
   - The `render(throttle:)` method calls `buildNSAttributedString(markdown:baseDir:)` which now lives in the renderer module — this is a file-scope function, so it stays accessible within the module

4. Build and verify no regressions.

### Step 4 — Update the Module Guide

In `1 Setup/Module Guides/4 Markdown Preview/guide.md`:

- **Key types section:** Add `MarkdownPreviewRenderer` (or the new files) to the list.
- **Technical Summary → Threading:** Add a note that `parseIntentKind` now uses Swift `AttributedString` semantic attributes instead of private `NSPresentationIntent` ObjC selectors.
- **Failure modes:** Update the "Markdown parse failure" entry to note that if Swift `AttributedString` removes semantic attributes in a future OS release, rendering degrades to plain text (no crash).

### Step 5 — Verify the issues are resolved

| Issue | Verification |
|---|---|
| ISS-053 | Open a `.md` file with `# Heading`, ` ```code```, `> blockquote`, `- list` — each renders with distinct visual styling |
| ISS-054 | `MarkdownPreviewViewModel.swift` contains only the view model class (no rendering helpers or types) |
| ISS-055 | No `perform(_:)` or `value(forKey:)` calls on `NSPresentationIntent`; all parsing goes through Swift `AttributedString` attributes |

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| `AttributedString` semantic attributes (`headerLevel`, etc.) are not publicly documented | Medium | They are observable in runtime `AttributedString` output with `.full` parsing. If unavailable, degrade to plain text with zero crash risk. |
| Run iteration performance impact | Low | `for run in attributed.runs` is O(n) in the number of semantic runs — typically ≤ the character count divided by segments. Same complexity as the current (non-functional) code. |
| Splitting the file breaks module-level function visibility | Low | File-scope functions in the same module are visible across files. `buildNSAttributedString` and `parseMarkdownSegment` are `private` and would need to change to `internal` — since they're in the same module, this compiles. |

## Success Criteria

- `# Heading 1` renders as a large bold font (28pt) in the Markdown Preview
- `` `code` `` renders in monospaced font at 12pt with a grey background
- `> blockquote` renders with indented, grey-coloured text
- `- list items` render with indentation and paragraph spacing
- `MarkdownPreviewViewModel.swift` drops from 366 lines to ~125 lines
- Zero `perform(_:)`, `value(forKey:)`, or other private-API calls in the rendering pipeline

## Post-Plan

- [ ] Move this plan to `Plans Completed/` when all steps are done.
- [ ] Update ISS-053, ISS-054, ISS-055 status to `Resolved` in `References/Issues.md`.
- [ ] Run `--target FoundationModule` + `--target MarkdownPreviewModule` to confirm build.
