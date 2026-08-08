---
plan: Vibe Rules alignment — top-three-file audit fixes
module: 3 Text Editor (3.1) + 10 ASCII Studio
created: 2026-06-16
status: complete
related_issues: ISS-136, ISS-137, ISS-138, ISS-139
---

## Purpose
Fix the force-unwrap violation (SR-2) and reduce responsibility sprawl (SR-6) in the three largest Swift source files, as identified by the code-review audit.

## Success Condition
- Force-unwrap on `EditorTextView.swift:612` is replaced with safe optional handling; the function returns a sensible fallback on failure.
- The extractive summarization logic is extracted from `EditorTextView.swift` into its own `ExtractiveSummarizer` type in a separate file.
- Terminal-integration helpers are extracted from `EditorViewModel.swift` into a dedicated `TerminalIntegration` helper type.
- The project builds with no new warnings or errors.
- `ASCIIStudioView.swift` decomposition is documented as deferred (too high-risk for this pass).

## Steps

### Part A — Fix force-unwrap (SR-2, ISS-136)

1. **Replace the force-unwrap in `extractiveSummary`**
   What: In `EditorTextView.swift` line 612, replace `sentences.firstIndex(of: $0.text)!` with `guard let` + `flatMap` so that any sentence whose text is unexpectedly absent from the original tokenized array is silently skipped rather than crashing the app.
   Why: SR-2 requires every failure path to be handled explicitly.

### Part B — Extract summarization to own type (SR-6, ISS-137)

2. **Create `ExtractiveSummarizer.swift`**
   What: New file `3 Text Editor/3.1 Text/ExtractiveSummarizer.swift` containing a `struct ExtractiveSummarizer` with a single static method `summary(of:maxSentences:) -> String` — carrying the `NLTokenizer`-based TF scoring logic currently in `EditorTextView.extractiveSummary`. Annotate the type with `public` visibility and add full DocC documentation (SW-4).
   Why: Extractive summarization is a distinct NLP concern unrelated to text-view editing. Extracting it honours SR-6 and makes the summarizer testable in isolation.

3. **Update `EditorTextView` to delegate**
   What: Replace the `extractiveSummary` method body with a delegation call to `ExtractiveSummarizer.summary(of:maxSentences:)`. Remove the `import NaturalLanguage` from `EditorTextView.swift` (it moves to the new file). Keep the `@objc summarizeSelectionLocally` method and the `SummaryPopoverContent` SwiftUI view in `EditorTextView.swift` — those are UI plumbing that belong with the text view.
   Why: The caller (the popover controller) is UI-layer code that depends on `NSTextView` geometry; it stays with the text view. Only the NLP algorithm moves.

### Part C — Extract terminal bridge from EditorViewModel (SR-6, ISS-139)

4. **Create `EditorTerminalBridge.swift`**
   What: New file `3 Text Editor/3.1 Text/EditorTerminalBridge.swift` containing an `enum EditorTerminalBridge` (no-instance namespace) with static methods extracted from `EditorViewModel`:
   - `sendSelection(to router: any InterPanelRouter, from textView: NSTextView)`
   - `runFile(url: URL, mode: EditorMode, router: any InterPanelRouter)`
   - `insertTerminalSelection(router: any InterPanelRouter, textView: NSTextView)`
   - `insertLastCommandOutput(router: any InterPanelRouter, textView: NSTextView)`
   - `editorSelectionOrCurrentLine(textView: NSTextView) -> String`
   - `insertText(_ text: String, at textView: NSTextView)`
   Why: These methods operate on `InterPanelRouter` + `NSTextView`, not on `EditorViewModel` state. Extracting them makes the view model's core responsibility — document lifecycle — clearer and makes the bridge testable independently.

5. **Update `EditorViewModel` to delegate**
   What: Replace the bodies of `sendSelectionToTerminal()`, `runCurrentFileInTerminal()`, `insertTerminalSelection()`, and `insertLastCommandOutput()` with one-line delegations to `EditorTerminalBridge`. Remove the now-unused `editorSelectionOrCurrentLine()` and `insertTextIntoEditor(_:at:)` private helpers from the view model.
   Why: The view model retains its public API (other modules call these methods by name) but the implementation moves out.

### Part D — ASCIIStudioView deferral

6. **No code change — document rationale**
   What: `ASCIIStudioView.swift` is too large to split safely in this pass. The three sub-views (image conversion controls, library browser, editable canvas) share `@State` bindings that would need cross-view coordination via a shared view model. A decomposition plan would need: (a) identifying the shared state boundary, (b) creating an `ASCIIStudioModel` observable object, (c) splitting the views, (d) regression-testing every interaction path. Mark ISS-138 as Deferred.
   Why: Rushing a split risks breaking the conversion pipeline, the editor integration, and the library. This needs a dedicated plan.
