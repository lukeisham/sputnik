---
plan: Fix conversion threading and render performance
module: 10 ASCII Studio
created: 2026-07-02
status: pending
related_issues: ISS-191, ISS-192, ISS-196, ISS-197
---

## Purpose
Move image-to-ASCII conversion off the main thread as the Module Guide already claims it does, supersede stale in-flight conversions during rapid slider changes, remove the undefined-behaviour pointer pattern in the pixel readers, and stop the grid canvas from redrawing every cell on every edit.

## Success Condition
- Converting a large image (near the 500×500-cell cap) does not visibly stall the UI (spinner/progress remains responsive, other panels stay interactive) — confirmed by profiling or by observing no main-thread hang in Instruments/the Xcode debugger during conversion.
- Dragging the width or brightness slider rapidly across its full range settles the canvas on the conversion matching the slider's *final* resting value, never an intermediate one — verified by dragging to a distinctive value and confirming the output matches that value exactly, repeated several times.
- `readPixels` and `detectEdges` no longer take the address of a local array across a call boundary that extends beyond the call itself; the `CGContext` creation and use are properly scoped.
- Editing a single cell in the editable canvas (tap-to-replace) does not force a full-grid redraw of every cell — confirmed by only the changed cell's rect being marked dirty (`setNeedsDisplay(_:)` with a specific rect) or by an instrumented draw-call counter in a test/debug build.
- All existing `ASCIIStudioModuleTests` still pass.

## Steps

- [ ] 1. **Move conversion to a truly detached background task**
   What: In `ASCIIStudioImageView.regenerate()` and `saveAtPreset(_:)`, replace `Task(priority: .userInitiated) { ... }` with `Task.detached(priority: .userInitiated) { ... }`, capturing only the `Sendable` `image` and `settings` values needed (not `self`/`model` directly), and hop back via `await MainActor.run { ... }` (or `@MainActor in` closure) only for the final state writes (`imageEditor.load`, `model.asciiPreview`, `model.isConverting`).
   Why: ISS-191 — a plain `Task` inside a `@MainActor`-isolated SwiftUI view inherits main-actor isolation, so the conversion currently runs on the main thread despite the Module Guide's Invariants section claiming otherwise (the same class of bug fixed as ISS-104 in the File Tree and ISS-157 in Foundation).

- [ ] 2. **Supersede in-flight conversions instead of racing them**
   What: Add a generation counter or cancellable-task-reference pattern to `ASCIIStudioModel` (e.g. `private var conversionTask: Task<Void, Never>?`), and in `regenerateOnChange()`/`regenerate()` cancel the previous task before starting a new one; inside the detached task, check `Task.isCancelled` before writing results back on `@MainActor`.
   Why: ISS-192 — today every slider tick during a drag spawns an independent, uncancelled task; results apply in completion order, not call order, so the canvas can visibly settle on a stale conversion mid-drag.

- [ ] 3. **Optionally debounce rapid slider changes**
   What: If cancellation alone (step 2) still produces excessive redundant conversion work during a fast drag, add a short debounce (reuse `SputnikShared`'s `DebounceTimer` if available to this module, or a small local equivalent) before triggering `regenerate()` from `onChange` handlers, so a drag settles once rather than converting on every intermediate tick.
   Why: Reduces wasted CPU during interactive slider dragging; cancellation (step 2) guarantees correctness, debouncing improves efficiency (SR-4) on top of it.

- [ ] 4. **Fix the pixel-buffer pointer lifetime in `readPixels` and `detectEdges`**
   What: In `ImageToASCIIConverter.readPixels` and `ASCIIEdgeDetector.detectEdges`, replace the `&rawData`/`&rawH`/`&rawV` inout-pointer pattern with `rawData.withUnsafeMutableBytes { rawBufferPointer in ... }`, creating the `CGContext` and performing the `draw(_:in:)` call (and, in `readPixels`'s case, returning the buffer as a `[UInt8]` copy) entirely inside the closure.
   Why: ISS-196 — the current pattern's implicit pointer from `&rawData` is only valid for the duration of the single call it's passed to; using the resulting `CGContext` afterward (as both functions do) is undefined behaviour in Swift, even though it happens to work today. This is a correctness/safety fix, not a behavior change.

- [ ] 5. **Bound `GridNSView`'s redraw to the changed region**
   What: In `MonoGridView.updateNSView`, instead of unconditionally calling `nsView.needsDisplay = true` on every update, compute the changed cell(s) (e.g. diff `selectedCell` and, where feasible, track which grid indices actually changed since the last update) and call `nsView.setNeedsDisplay(_:)` with just that cell's rect; in `GridNSView.draw(_:)`, use `dirtyRect` to skip cells entirely outside it rather than iterating the whole grid unconditionally.
   Why: ISS-197 — a single tap-to-edit currently forces a full redraw of up to ~125,000 individual glyph draws at maximum grid size; bounding to the dirty rect makes single-cell edits cheap regardless of canvas size (SR-4), matching the fix direction already planned for the Terminal's `TerminalTextView` (ISS-187).

- [ ] 6. **Add/extend tests**
   What: In `Tests/ASCIIStudioModuleTests.swift`, add a test that starts a conversion, immediately starts a second with different settings, and asserts only the second's result is ever applied (may require exposing the generation/cancellation state for testing, or testing at the `ImageToASCIIConverter` level with an injected cancellation check). Add a `readPixels`/`detectEdges` correctness test post-refactor (same output for a known fixture image) to catch any accidental behavior change from the pointer-lifetime fix.
   Why: Locks in the supersession fix and confirms the memory-safety refactor didn't change conversion output.

- [ ] 7. **Manual verification and profiling pass**
   What: Run the app with a large image; drag the width/brightness sliders rapidly and confirm the canvas settles correctly; use Instruments (Time Profiler) or simple main-thread-blocking observation to confirm conversion no longer stalls the UI; edit single cells in a large canvas and confirm draw responsiveness.
   Why: Threading and render-performance fixes are best confirmed by direct observation of responsiveness, not just unit tests.

## Risks and Constraints
- SW-1: `Task.detached` must not capture `self`/`model`/`imageEditor` directly (all `@MainActor`-isolated types) — only `Sendable` value types (`NSImage` is not `Sendable` by default; confirm the existing code's handling of `image` across the task boundary is already safe, or wrap appropriately).
- SR-4: this plan's whole point is bounded, off-main-thread work — no step may reintroduce main-thread pixel processing or unbounded per-frame redraw.
- Step 4 is a pure refactor with no intended behavior change — verify converter/edge-detector output is bit-identical (or visually identical) before/after via the new test in step 6.
- Coordinate with the companion "Fix data-scrambling and crash bugs" plan if both are in flight — they touch overlapping files (`ImageToASCIIConverter.swift`) but different functions, so conflicts should be minimal; land either order.

## Files Affected
- `10 ASCII Studio/Sources/ASCIIStudioImageView.swift` — `regenerate()`, `saveAtPreset(_:)`, `regenerateOnChange()`
- `10 ASCII Studio/Sources/ASCIIStudioModel.swift` — conversion task/generation tracking
- `10 ASCII Studio/Sources/ImageToASCIIConverter.swift` — `readPixels`
- `10 ASCII Studio/Sources/ASCIIEdgeDetector.swift` — `detectEdges`
- `10 ASCII Studio/Sources/MonoGridView.swift` — dirty-rect redraw
- `10 ASCII Studio/Tests/ASCIIStudioModuleTests.swift` — new test cases

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[10 ASCII Studio] Fix conversion threading and render performance`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
