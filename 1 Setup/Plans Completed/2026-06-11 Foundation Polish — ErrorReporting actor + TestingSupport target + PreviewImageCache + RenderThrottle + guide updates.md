---
plan: Foundation Polish — ErrorReporting actor + TestingSupport target + PreviewImageCache + RenderThrottle + guide updates
module: 2 Foundation (2.7 Utilities)
created: 2026-06-11
status: pending
related_issues: none
---

## Purpose
Add four self-contained Foundation utilities — ErrorReporting actor, PreviewImageCache actor, RenderThrottle utility, and TestingSupport mocks — to close all recently flagged "minor-minor" polish items without touching the module dependency graph.

## Success Condition
- All four new types compile under strict concurrency checking (SW-1).
- No force-unwraps added anywhere (SR-2).
- PreviewImageCache is consumed by at least Markdown Preview, HTML Preview, and PDF Viewer.
- RenderThrottle reduces CPU usage on large live files (observable in Activity Monitor).
- `swift test --package-path 2\ Foundation` passes with at least one new unit test running against TestingSupport mocks.
- All four Module Guides (2 Foundation overview, 2.7 Utilities, 9 Resources) updated and cross-reference the new types.
- Sitemap updated.

## Steps

- [ ] 1. **Create ErrorReporting actor**
      What: Add `ErrorReporting.swift` to `2 Foundation/2.7 Utilities/` — a `Sendable` actor with `log(_:)`, `report(_:)` and a shared `.shared` singleton. It writes to both `os_log` and an in-memory ring buffer (for future telemetry).
      Why: Centralises all non-fatal error logging so callers across modules have a single source of truth instead of sprinkling `os_log` calls with inconsistent categories (SR-2, SR-1).

- [ ] 2. **Create PreviewImageCache actor**
      What: Add `PreviewImageCache.swift` to `2 Foundation/2.7 Utilities/` — an actor wrapping `NSCache<NSURL, NSImage>` with a generation counter for cache invalidation, `image(for: URL)` / `setImage(_:for: URL)` methods, and automatic downsampling for images larger than a configurable max dimension.
      Why: Eliminates duplicate image decoding when the same image is referenced in Markdown, HTML, and PDF previews (SR-3 — low RAM usage), directly supporting the "9 Resources Image display" work.

- [ ] 3. **Create RenderThrottle utility**
      What: Add `RenderThrottle.swift` to `2 Foundation/2.7 Utilities/` — a struct wrapping the existing `DebounceTimer` with a generation-coalescing counter, exposed as `throttle(render:)`. The caller passes a render closure; if a newer generation arrives before the debounce interval fires, the previous closure is cancelled.
      Why: Prevents redundant preview re-renders during fast typing or terminal output floods, keeping the UI thread free (SR-4 — fast and efficient).

- [ ] 4. **Create TestingSupport target**
      What: Add `TestingSupport.swift` to `2 Foundation/2.7 Utilities/` with `@testable` mocks: `MockInterPanelRouter`, `MockAppState`, `MockWindowState`. Update `2 Foundation/Package.swift` to add a `TestingSupport` library target (test-only dependency on Foundation). Update root `Package.swift` to expose TestingSupport to the `App-Sputnik` target for XCTest.
      Why: Makes router/state/window logic testable without coupling test infrastructure into production code (SW-1).

- [ ] 5. **Wire ErrorReporting into AI monitors**
      What: In `MainAIMonitor.swift` and `SupportingAIMonitor.swift`, replace direct `os_log` calls with `ErrorReporting.shared.log(...)` or `.report(...)` for non-fatal errors.
      Why: Consolidates all AI-related error logging into the central reporter (SR-2).

- [ ] 6. **Wire PreviewImageCache into preview modules**
      What: In `MarkdownRenderView.swift`, `HTMLPreviewView.swift`, and `PDFViewerViewModel.swift`, replace direct image loading with `PreviewImageCache.shared.image(for:)` / `setImage(_:for:)`.
      Why: Shares decoded image data across all three preview panels, reducing peak RAM (SR-3).

- [ ] 7. **Wire RenderThrottle into render paths**
      What: Wrap preview render methods in Markdown/HTML/PDF previews and the terminal renderer with `RenderThrottle.throttle(render:)`.
      Why: Prevents redundant re-renders during rapid input (SR-4).

- [ ] 8. **Update Package.swift files**
      What: Add the `TestingSupport` target to `2 Foundation/Package.swift`. Add corresponding dependency in root `Package.swift`.
      Why: SPM must know about the new target for `swift test` to discover it.

- [ ] 9. **Update Module Guides**
      What:
      - `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md` — add section "2.7.4 Error & Performance Utilities"
      - `1 Setup/Module Guides/2 Foundation/2.7 Utilities/guide.md` — expand with full API docs for ErrorReporting, PreviewImageCache, RenderThrottle, and TestingSupport
      - `1 Setup/Module Guides/9 Resources/guide.md` — note that PreviewImageCache is now the canonical image resolver
      Why: Each guide is the source of truth for its module's design intent; new utilities must be documented there (per module guide format).

- [ ] 10. **Run tests**
      What: `swift test --package-path 2\ Foundation` — confirm TestingSupport mocks enable at least one passing test (e.g. `MockInterPanelRouter.open(_:)` returns the expected session ID).
      Why: Validates the TestingSupport target builds and mocks work.

- [ ] 11. **Manual smoke test**
      What: Open a large Markdown file + HTML file + PDF side-by-side. Verify cache hits by checking that switching between previews does not trigger re-decoding (RAM stays flat). Verify that fast typing in the editor does not cause visual stutter (RenderThrottle active).
      Why: Functional validation that the three utilities interact correctly (SR-3, SR-4).

- [ ] 12. **Update sitemap and close out**
      What: Run `python3 _gen_sitemap.py` from the project root to update line counts. Move this plan to `Plans Completed/`.
      Why: Keeps repo metadata in sync; plan lifecycle requires the move as the final act.

## Risks and Constraints
- **Foundation changes affect every module** — new types must be exposed only as protocols or tokens where cross-module access is needed; concrete types stay inside 2.7 Utilities (SR-1).
- **TestingSupport must be test-only** — never link TestingSupport into production builds (SR-1).
- **No third-party dependencies** — all new types use only Foundation, os_log, and NSCache (Vibe Coding Rules).
- **Plan is immutable once approved** — if scope changes, a new plan must be created.

## Files Affected
- `2 Foundation/2.7 Utilities/ErrorReporting.swift` — **create**: ErrorReporting actor
- `2 Foundation/2.7 Utilities/PreviewImageCache.swift` — **create**: PreviewImageCache actor
- `2 Foundation/2.7 Utilities/RenderThrottle.swift` — **create**: RenderThrottle struct
- `2 Foundation/2.7 Utilities/TestingSupport.swift` — **create**: MockInterPanelRouter, MockAppState, MockWindowState
- `2 Foundation/2.7 Utilities/MainAIMonitor.swift` — **edit**: wire ErrorReporting for non-fatal errors
- `2 Foundation/2.7 Utilities/SupportingAIMonitor.swift` — **edit**: wire ErrorReporting for non-fatal errors
- `4 Markdown Preview/MarkdownRenderView.swift` — **edit**: use PreviewImageCache
- `8 HTML Preview/HTMLPreviewView.swift` — **edit**: use PreviewImageCache
- `5 PDF Viewer/PDFViewerViewModel.swift` — **edit**: use PreviewImageCache
- `7 Terminal/TerminalRenderer.swift` — **edit**: wrap render with RenderThrottle
- `3 Text Editor/3.1 Text/EditorView.swift` — **edit**: wrap live-update render with RenderThrottle
- `2 Foundation/Package.swift` — **edit**: add TestingSupport target
- `Root Package.swift` — **edit**: expose TestingSupport to App-Sputnik for XCTest
- `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md` — **edit**: add "2.7.4 Error & Performance Utilities" section
- `1 Setup/Module Guides/2 Foundation/2.7 Utilities/guide.md` — **edit**: expand API docs for four new types
- `1 Setup/Module Guides/9 Resources/guide.md` — **edit**: note PreviewImageCache as canonical resolver
- `sitemap.md` — **edit**: auto-updated by `_gen_sitemap.py`

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (tests pass + smoke test confirms RAM/CPU improvements)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation] Foundation Polish — ErrorReporting + TestingSupport + PreviewImageCache + RenderThrottle + guide updates`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
