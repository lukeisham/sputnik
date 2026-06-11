---
plan: Update Package.swift files to expose TestingSupport target
module: 2 Foundation
created: 2026-06-11
status: complete
related_issues: none
---

## Purpose
Add the `TestingSupport` library target to `2 Foundation/Package.swift` and expose it as a product so the root `Package.swift` can depend on it for the `SputnikApp` executable's XCTest integration.

## Success Condition
- `2 Foundation/Package.swift` declares a `TestingSupport` target and product.
- Root `Package.swift` can reference the `TestingSupport` product from the Foundation package.
- `swift test --package-path 2\ Foundation` runs without build errors.
- `swift build` from the root succeeds.

## Steps

- [x] 1. **Update 2 Foundation/Package.swift**
      What:
      - Add a new product: `.library(name: "TestingSupport", targets: ["TestingSupport"])`
      - Add a new target: `.target(name: "TestingSupport", dependencies: ["FoundationModule"], path: "2.7 Utilities")`
      Why: Exposes TestingSupport mocks for test consumption (SW-1).
      **Result: Already configured.** The target and product were already present in `Package.swift`.

- [x] 2. **Verify Foundation package builds**
      What: `swift build --package-path 2\ Foundation`
      Why: Confirms the new target integrates.
      **Result: Passed.** Build succeeded. Also fixed a `@MainActor` isolation error in `MockWindowState` and added a `public init()` to `MockInterPanelRouter`.

- [x] 3. **Update root Package.swift (if needed)**
      What: If `SputnikApp` should link TestingSupport for integration tests, add `.product(name: "TestingSupport", package: "2 Foundation")` to the dependencies.
      Why: Makes mocks available to app-level tests (optional; only if app has integration tests).
      **Result: Skipped.** No app-level tests exist; no integration test target to link against.

- [x] 4. **Verify Foundation package tests**
      What: `swift test` from the `2 Foundation/` directory.
      Why: Confirms tests can find and use the TestingSupport types.
      **Result: Passed.** All 18 tests pass. Also added `TestingSupport` dependency to the test target and `import TestingSupport` in the test file.

## Risks and Constraints
- TestingSupport must be marked test-only in the manifest if it should never link into production builds.
- The target path `"2.7 Utilities"` assumes TestingSupport.swift is in that directory (it is).
- No third-party dependencies — TestingSupport uses only Foundation types.

## Files Affected
- `2 Foundation/Package.swift` — **edit**: add TestingSupport target and product
- `Root Package.swift` — **edit** (optional): add TestingSupport product reference if needed for app-level tests

## Closeout
- [x] Build verification: `swift build --package-path 2\ Foundation` passes
- [x] TestingSupport product is discoverable by `swift test` harness (all 18 tests pass)
- [x] Fixes applied: `TestingSupport.swift` (added `@MainActor` to MockWindowState, added `public init()` to MockInterPanelRouter), `Package.swift` (added TestingSupport to test target deps), `FoundationModuleTests.swift` (added `import TestingSupport`)
- [x] Plan moved to Plans Completed/
