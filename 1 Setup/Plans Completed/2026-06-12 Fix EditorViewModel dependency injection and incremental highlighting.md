---
plan: Fix EditorViewModel dependency injection and incremental syntax highlighting
status: new
created: 2026-06-12
author: Zed (code analysis)
issues: ISS-056, ISS-057
---

## Summary

Two architectural issues in the Text Editor (module 3.1):

1. **ISS-056 (Medium):** `EditorViewModel` looks up dependencies by walking `NSApp.delegate as? AppDelegate` in three places instead of receiving them via constructor injection. Brittle in tests and inconsistent with the rest of the codebase.

2. **ISS-057 (Low):** `SyntaxHighlighter` re-highlights the full document on every keystroke — O(n × m) per text change where n = document length and m = regex patterns. Most modern editors use range-based or incremental highlighting.

---

## Issue 1: Dependency Injection (ISS-056)

### Current State

Three places in `EditorViewModel` reach through the global app delegate:

| Location | Lines | What it fetches |
|---|---|---|
| `init()` | 80–86 | `AppState` to call `registerEditorCommandHandler(self)` |
| `recoveryStore` lazy init | 66–73 | `PersistenceService` from `appDelegate.persistenceService` |
| `renderAsHTML()` | 268–273 | `AppState.router` via `appDelegate.appState?.router` |

This pattern:
- Fails silently if `NSApp.delegate` is not an `AppDelegate` (returns `nil`, no error)
- Cannot be tested without mocking `NSApp` and `AppDelegate`
- Is inconsistent with every other module in the codebase (e.g. `FileTreeViewModel` receives `WindowState` and `InterPanelRouter` via `configure(windowState:router:)`)
- Hides real dependencies from the initialiser signature — callers don't know what the view model needs

### Design

Add explicit constructor parameters. The `EditorViewModel` currently has a parameterless `public init()`. Change it to accept the three dependencies it actually needs:

```swift
public init(
    appState: AppState,
    persistenceService: PersistenceService
) {
    self.appState = appState
    self.persistenceService = persistenceService
    appState.registerEditorCommandHandler(self)
    self.recoveryStore = CrashRecoveryStore(persistence: persistenceService)
}
```

The `router` is already accessible through `appState.router` — no separate parameter needed.

### What changes

**`EditorViewModel.swift`:**
- Add `private let appState: AppState` and `private let persistenceService: PersistenceService` fields
- Replace `recoveryStore` lazy closure with direct initialisation in `init`
- Remove the `NSApp.delegate` casts in `init()`, `recoveryStore`, and `renderAsHTML()`
- `renderAsHTML()` reads `appState.router` directly instead of going through the app delegate

**`TextEditorPanel.swift`:**
- Currently takes `viewModel: EditorViewModel` as a `@Bindable` parameter
- The caller (`ContentView` or wherever the panel is constructed) must now pass `appState` and `persistenceService` when creating the view model

**`ContentView.swift` (App-Sputnik):**
- Wherever `EditorViewModel()` is created, change to `EditorViewModel(appState: appState, persistenceService: persistenceService)`

### Migration path

Since `EditorViewModel` is created in multiple places, use a single creation point — the window's `ContentView` — and pass the already-created view model to `TextEditorPanel`. This matches how other panels receive their view models (e.g. `FileTreePanel.init(router:)`).

---

## Issue 2: Incremental Syntax Highlighting (ISS-057)

### Current State

```swift
public func highlight(mode: EditorMode) {
    // ...
    let text = await MainActor.run { storage.string }
    let attrs = self.buildAttributes(for: mode, text: text)  // regex on full text

    await MainActor.run {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)  // clear ALL colours
        for (range, color) in attrs {                           // re-apply ALL colours
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
        storage.endEditing()
    }
}
```

Every keystroke triggers regex matching on the entire document. For a 10,000‑line Markdown file this means every regex pattern (headers, bold, italic, code, links, lists — typically 10–15 patterns) scans 10,000 lines to produce the colour attribute array, then the entire range is cleared and rewritten.

### Design

Two approaches, in increasing order of sophistication:

**Approach A — Range-based re-highlight (Recommended first step)**

Pass the edited range to `highlight(mode:editedRange:)`. Only re-highlight that range plus a look-behind margin (e.g. 5 lines before the edit for multi-line constructs like fenced code blocks or list continuations).

```swift
/// Re-highlights a range of the document.
/// - Parameter editedRange: The character range that changed. `nil` = full document (initial load).
public func highlight(mode: EditorMode, editedRange: NSRange? = nil) {
    guard mode != .plainText else { return }
    
    Task(priority: .utility) { [weak self] in
        guard let self, let storage = self.textStorage else { return }
        let text = await MainActor.run { storage.string }
        
        // Expand range to include surrounding lines for multi-line constructs.
        let highlightRange = expandedRange(for: editedRange, in: text)
        let segment = (text as NSString).substring(with: highlightRange)
        
        let attrs = self.buildAttributes(for: mode, text: segment,
                                         baseOffset: highlightRange.location)
        
        await MainActor.run { [weak self] in
            guard let self, let storage = self.textStorage else { return }
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: highlightRange)
            for (range, color) in attrs {
                guard range.location + range.length <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
            storage.endEditing()
        }
    }
}

/// Expands a character range to include full surrounding lines.
/// If `range` is nil, returns the full document range.
private func expandedRange(for range: NSRange?, in text: String) -> NSRange {
    guard let range = range else {
        return NSRange(location: 0, length: (text as NSString).length)
    }
    let nsText = text as NSString
    let lookBackLines = 5  // enough to catch fenced code block starts
    var startLine = max(0, nsText.lineRange(for: range).location)
    // Walk back N lines
    for _ in 0..<lookBackLines {
        guard startLine > 0 else { break }
        startLine = nsText.lineRange(for: NSRange(location: startLine - 1, length: 0)).location
    }
    let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
    let endLocation = min(nsText.length, lineRange.upperBound)
    return NSRange(location: startLine, length: endLocation - startLine)
}
```

The `Coordinator.textDidChange` already receives `Notification` with the edited range via `NSTextView.textDidChange`. Extract it from the notification's `userInfo`:

```swift
public func textDidChange(_ notification: Notification) {
    viewModel.isDirty = true
    
    // Extract the edited character range from the notification.
    let editedRange: NSRange? = (notification.userInfo?["NSRange"] as? NSValue)?.rangeValue
    
    let currentMode = viewModel.mode
    if currentMode != .plainText {
        highlightDebounceTimer?.cancel()
        highlightDebounceTimer?.schedule(delay: 0.3) { [weak self] in
            self?.syntaxHighlighter?.highlight(mode: currentMode, editedRange: editedRange)
        }
    }
    // ...
}
```

**Approach B — Line-based invalidation (Future enhancement)**

Maintain a `Set<Int>` of dirty line numbers. The highlight pass only processes lines in the dirty set and their neighbours. This avoids regex overhead on unchanged lines entirely. Significantly more complex — requires mapping character ranges to line numbers, tracking what's been invalidated, and handling bulk operations (paste, undo). **Not recommended for this plan** — Approach A gives 90% of the benefit for 10% of the complexity.

### Chosen approach: **Approach A**

The range-based approach is straightforward, handles the common case (single-keystroke edits, paste, cut), and the look-behind margin catches multi-line syntax constructs. A full re-highlight still happens on initial document load (when `editedRange` is `nil`).

---

## Steps

### Step 1 — Fix dependency injection (ISS-056)

1. **Edit `EditorViewModel.swift`:**
   - Add stored properties:
     ```swift
     private let appState: AppState
     private let persistenceService: PersistenceService
     ```
   - Replace the parameterless `init()`:
     ```swift
     public init(appState: AppState, persistenceService: PersistenceService) {
         self.appState = appState
         self.persistenceService = persistenceService
         appState.registerEditorCommandHandler(self)
         self.recoveryStore = CrashRecoveryStore(persistence: persistenceService)
     }
     ```
   - Replace the lazy `recoveryStore` closure with a simple `private let recoveryStore: CrashRecoveryStore?`
   - Replace `renderAsHTML()`:
     ```swift
     public func renderAsHTML() async throws {
         guard htmlModeActive, let url = fileURL else { return }
         await appState.router?.open(url)
     }
     ```

2. **Find all `EditorViewModel()` creation sites** (grep for `EditorViewModel()`):
   - `TextEditorPanel` — change init to accept an already-created `EditorViewModel`
   - `ContentView` — create `EditorViewModel(appState:appState, persistenceService: persistenceService)` and pass it to `TextEditorPanel`

3. **Build and verify:** `swift build --target TextEditorModule` passes.

### Step 2 — Implement range-based highlighting (ISS-057)

1. **Edit `SyntaxHighlighter.swift`:**
   - Add `editedRange: NSRange? = nil` parameter to `highlight(mode:)` → `highlight(mode:editedRange:)`
   - Add the `expandedRange(for:in:)` private helper
   - Replace the full-range `removeAttribute` with range-scoped

2. **Edit `EditorView.swift` (Coordinator):**
   - Extract `NSRange` from `textDidChange` notification's `userInfo["NSRange"]`
   - Pass it to `syntaxHighlighter?.highlight(mode:editedRange:)`

3. **Edit `EditorViewModel.swift`:**
   - The initial load call in `openDocument` triggers `updateNSView` which calls `SyntaxHighlighter.highlight(mode:)` — this will use the default `editedRange: nil` for a full initial highlight. Correct.

4. **Build and verify:** `swift build --target TextEditorModule` passes.

### Step 3 — Verify with large files

1. Create a ~5,000 line Markdown file (use a script to generate repeated headings/text).
2. Open it in Sputnik and type rapidly in the middle of the file.
3. Verify that the UI remains responsive and highlighting tracks edits correctly.
4. Check that multi-line constructs (fenced code blocks spanning the edited range boundary) are still highlighted — the look-behind margin of 5 lines should handle this.

### Step 4 — Update the Module Guide

In `1 Setup/Module Guides/3 Text Editor Window/3.1 Text/guide.md`:

- **Key types → `EditorViewModel`:** Update the description to note dependencies are injected via `init(appState:persistenceService:)`.
- **Threading model:** Add a note that syntax highlighting uses range-based re-highlight (expanded to nearest line boundaries + 5-line look-behind).
- **Failure modes:** Remove any reference to silent `NSApp.delegate` fallback.

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| Missing an `EditorViewModel()` creation site | Medium | Grep for `EditorViewModel(` and `EditorViewModel()` — the parameterless init will produce a compile error everywhere it's used, so the build will catch every miss. |
| `NSTextView.textDidChange` notification doesn't include `NSRange` in `userInfo` | Medium | Test on first run. If absent, fall back to nil (full re-highlight) — same behaviour as today. AppKit documentation confirms the notification posts the range via `NSRange` in `userInfo`. |
| 5-line look-behind isn't enough for very long fenced code blocks | Low | A 5-line margin covers the vast majority of real-world cases. A fenced code block ``````` opened 6+ lines above the edit is unlikely to need colour changes that far away. Tunable via the `lookBackLines` constant. |

## Success Criteria

- `EditorViewModel` has zero `NSApp.delegate` casts in its implementation
- `EditorViewModel(appState:persistenceService:)` is the only public initialiser
- `SyntaxHighlighter.highlight(mode:editedRange:)` only re-colours the affected range (plus margin)
- Build passes for `TextEditorModule`
- No visual regression in syntax highlighting correctness

## Post-Plan

- [ ] Move this plan to `Plans Completed/` when all steps are done.
- [ ] Update ISS-056 and ISS-057 status to `Resolved` in `References/Issues.md`.
- [ ] Grep for any remaining `NSApp.delegate as? AppDelegate` patterns in module 3 to catch any I missed.
