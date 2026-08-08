---
plan: HTML preview — crash, placeholder, and CSS-injection caching
module: 8 HTML Preview
created: 2026-06-13
status: complete
related_issues: ISS-085, ISS-086, ISS-092
split_from: 2026-06-13 4+8 Preview sync correctness and performance.md (deleted 2026-06-14 after split)
---

> **Split 1 of 3** carved from the original "Preview sync correctness and performance" plan.
> Owns the module-8 (HTML preview) work: one crash fix, one placeholder-reload guard, and the
> scroll-sync hot-path caching. Independent of the two Markdown splits — can land in any order
> relative to them.
>
> Does **not** touch `HTMLPreviewCoordinator.throttledLoad`'s inner Task — that is owned by the
> existing ISS-084 plan (`2026-06-13 3 Editor concurrency and save-safety hardening.md`, step 4).

## Purpose
Fix three HTML-preview defects: a crash on head-only HTML (ISS-086), an always-reload of the
placeholder web view on every AppState change (ISS-092), and a main-thread stutter under scroll
sync caused by running O(n) CSS injection on every `updateNSView` call (ISS-085).

## Success Condition
- `swift build` clean across all packages — no new warnings in module 8.
- An HTML file ending with `</head>` and no body can be edited without crashing (ISS-086).
- Opening an HTML preview and switching app focus does not reload/reflash the placeholder
  (ISS-092).
- With scroll sync enabled, scrolling the editor through a 200-line HTML file produces no visible
  stutter on the main thread — verified by Instruments Time Profiler showing
  `htmlByInjectingOverrides` absent from the main-thread hot path during scroll (ISS-085).

## Steps

- [x] 1. **Fix the `splitHTML` crash on head-only HTML (ISS-086)**
  File: `8 HTML Preview/HTMLPreviewCoordinator.swift:140`
  Change `html[html.startIndex...headEndRange.upperBound]` to
  `html[html.startIndex..<headEndRange.upperBound]`. The closed-range subscript traps when
  `upperBound == endIndex`; the half-open form handles it correctly. Verify with a unit test that
  passes `"<html><head></head>"` (no body) and `"<html><head></head><body></body>"` to
  `splitHTML` and asserts no crash and correct head/body split.

- [x] 2. **Guard the HTML placeholder reload (ISS-092)**
  File: `8 HTML Preview/HTMLPreviewView.swift` and `8 HTML Preview/HTMLPreviewCoordinator.swift`
  Add `var isShowingPlaceholder: Bool = false` to `HTMLPreviewCoordinator`. In
  `HTMLPreviewView.updateNSView`, before calling `webView.loadHTMLString(placeholderHTML, ...)`,
  guard with `guard !context.coordinator.isShowingPlaceholder else { return }`. Set
  `isShowingPlaceholder = true` after loading and reset it to `false` whenever a real HTML session
  is loaded (at the top of the `guard let session` branch).

- [x] 3. **Move CSS injection and image rewriting out of the scroll-sync hot path (ISS-085)**
  File: `8 HTML Preview/HTMLPreviewView.swift`
  The problem: `htmlByInjectingOverrides` (O(n) regex) runs on every `updateNSView` call, which
  includes every scroll tick when sync is on.
  Fix: cache the last-injected result in the coordinator alongside the input hash:
  ```swift
  // In HTMLPreviewCoordinator:
  var lastStyledHTML: String = ""
  var lastStyledInputHash: Int = 0
  ```
  In `updateNSView`, compute `let inputHash = session.text.hashValue ^ settings.stableHash` (where
  `stableHash` is a lightweight hash of the two settings properties that affect CSS injection —
  font postscript name + point size + background hex). Only call `htmlByInjectingOverrides` when
  `inputHash != coordinator.lastStyledInputHash`; otherwise use `coordinator.lastStyledHTML`
  directly before calling `throttledLoad`. This reduces the hot path under scroll sync to a single
  integer comparison.
  Note: `stableHash` is a simple computed property on `SettingsStore` (or computed inline)
  combining the font and background properties — no new dependencies required.

- [x] 4. **Re-verify and update the Module Guide**
  After steps 1–3 pass, update `1 Setup/Module Guides/8 HTML Preview/guide.md` to reflect:
  (a) CSS injection cached by input hash; (b) placeholder reload guarded by `isShowingPlaceholder`;
  (c) `splitHTML` crash fixed. Set `status: stable`, `last_updated: 2026-06-13`,
  `last_verified: 2026-06-13`.

## Execution Order
Steps 1–2 are independent and safe to do in either order. Step 3 changes a hot path — do it after
confirming the build is clean. Step 4 is always last.

## Risks and Constraints
- **Step 3 — `stableHash`:** The hash must cover every property of `SettingsStore` that flows into
  `htmlByInjectingOverrides`. Currently that is `resolvedHtmlPreviewFont` (postscript name + point
  size) and `htmlPreviewBackground` (Color). If new settings are added to that function later,
  `stableHash` must be updated too. Add a comment to `htmlByInjectingOverrides` listing all inputs
  that must be represented.
- **Does not touch `HTMLPreviewCoordinator.throttledLoad`'s inner Task** — owned by the ISS-084
  plan. Coordinate landing order if both are in flight, but they edit different code in the file.

## Files Affected
- `8 HTML Preview/HTMLPreviewCoordinator.swift` — steps 1, 2, 3.
- `8 HTML Preview/HTMLPreviewView.swift` — steps 2, 3.
- `1 Setup/Module Guides/8 HTML Preview/guide.md` — step 4.

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide updated (`status` + `last_updated`)
- [ ] Changes committed: `[8 HTML] Preview crash, placeholder, and CSS-injection caching`
- [ ] Pushed to GitHub
- [x] Plan moved to Plans Completed/
- [x] Mark ISS-085, ISS-086, ISS-092 Resolved in Issues.md with the fix summary
