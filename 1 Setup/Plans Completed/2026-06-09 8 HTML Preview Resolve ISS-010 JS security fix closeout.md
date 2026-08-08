---
plan: Resolve ISS-010 — JS security fix closeout
module: 8 HTML Preview
created: 2026-06-09
status: pending
related_issues: ISS-010
---

## Purpose
Mark ISS-010 as Resolved: the fix is already fully implemented in source — the deprecated
`javaScriptEnabled` API has been replaced and the selection-capture `WKUserScript` is in
place — but Issues.md was never updated to reflect that.

## Success Condition
`ISS-010` row in `1 Setup/References/Issues.md` reads `Resolved` with a concise note.
No Swift source file contains `javaScriptEnabled`. Commit lands on `main`.

## Steps

1. **Verify fix in source**
   What: Confirm `8 HTML Preview/HTMLPreviewView.swift` uses
   `configuration.defaultWebpagePreferences.allowsContentJavaScript = false` (not the
   deprecated `configuration.preferences.javaScriptEnabled`), that the `WKUserScript`
   selection listener is injected, and that `HTMLPreviewCoordinator` conforms to
   `WKScriptMessageHandler`.
   Why: The plan closes an open issue; we must be certain the implementation matches the
   planned fix before marking it resolved.

2. **Update ISS-010 status in Issues.md**
   What: Change the `Status` cell for ISS-010 from
   `Open — 2026-06-09: planned fix …` to
   `Resolved — 2026-06-09: implemented in 8 HTML Preview/HTMLPreviewView.swift and
   HTMLPreviewCoordinator.swift as part of plan "2026-06-09 2 Foundation More Context
   shared lookup utility" (now in Plans Completed). Deprecated javaScriptEnabled removed;
   allowsContentJavaScript = false + WKUserScript selection capture in place.`
   Why: Issues.md is append-only and the source of truth for open issues; an unresolved
   entry creates false noise for future planning sessions.

3. **Commit**
   What: Stage only `1 Setup/References/Issues.md`. Commit message:
   `[8 HTML Preview] Resolve ISS-010 — mark JS security fix as resolved`
   Why: Keeps the resolution traceable in git history.

4. **Move plan to Plans Completed/**
   What: Move this file from `Plans New/` to `Plans Completed/`.
   Why: Required closeout step per `!GenerateAPlan` rules — a plan is not done until moved.

## Risks and Constraints
- Issues.md is append-only (per its own header). The status cell is the only field that
  changes; do not alter description, severity, or any other column.
- No Swift code changes needed — this is documentation-only.

## Files Affected
- `1 Setup/References/Issues.md` — update ISS-010 Status cell to Resolved

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (grep confirms no `javaScriptEnabled` in Swift; ISS-010 reads Resolved)
- [ ] Module Guide(s) updated (`status` + `last_updated`) — Module 8 guide already current; no change needed
- [ ] Changes committed: `[8 HTML Preview] Resolve ISS-010 — mark JS security fix as resolved`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
