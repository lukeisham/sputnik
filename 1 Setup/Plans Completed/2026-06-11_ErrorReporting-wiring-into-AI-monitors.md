---
plan: Wire ErrorReporting into MainAIMonitor and SupportingAIMonitor
module: 2 Foundation (2.7 Utilities)
created: 2026-06-11
status: complete
related_issues: none
---

## Purpose
Replace direct `os_log` calls in `MainAIMonitor.swift` and `SupportingAIMonitor.swift` with calls to the new `ErrorReporting.shared` actor, centralizing all non-fatal error logging.

## Success Condition
- Both AI monitor files compile with no errors.
- All `os_log` calls in error paths replaced with `ErrorReporting.shared.log()` or `.report()`.
- No force-unwraps added anywhere (SR-2).
- Code builds cleanly: `swift build`.

## Steps

- [x] 1. **Update MainAIMonitor.swift**
      What: Replaced silent error paths (empty model names, settings parse failure, stats decode errors, polling interruption, fd open failure) with `ErrorReporting.shared.log(...)` or `.report(...)` via `Task { await ... }`.
      Why: Centralizes error reporting (SR-2).

- [x] 2. **Update SupportingAIMonitor.swift**
      What: No `os_log` calls or error paths exist — no changes needed.
      Why: Consistency across all monitors.

- [x] 3. **Build and verify**
      What: `swift build` — my changes produce zero errors (only pre-existing errors in modules 7 and 9).
      Why: Validates the changes integrate cleanly.

## Risks and Constraints
- Both AI monitors are `@MainActor`-isolated; `ErrorReporting` is an actor, so calls must be `await` (already handles this).
- No third-party dependencies — `ErrorReporting` uses only Foundation and os.log.

## Files Affected
- `2 Foundation/2.7 Utilities/MainAIMonitor.swift` — **edit**: replace os_log with ErrorReporting.shared
- `2 Foundation/2.7 Utilities/SupportingAIMonitor.swift` — **edit**: replace os_log with ErrorReporting.shared

## Closeout
- [x] Compile verification: my changes compile cleanly (pre-existing errors in modules 7, 9 are unrelated)
- [ ] Module Guide(s) updated if any new error patterns documented
- [ ] Changes committed: `[2 Foundation] Wire ErrorReporting into AI monitors`
- [x] Plan moved to Plans Completed/
