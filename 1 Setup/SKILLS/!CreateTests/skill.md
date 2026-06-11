# Skill: !CreateTests

## Purpose
Generate Swift Testing unit tests for a Sputnik module by reading its Module Guide and source code, then writing a ready-to-compile test file with a coverage summary.

---

## Usage

```
!CreateTests: <module-name>
```

**Examples:**
```
!CreateTests: Terminal
!CreateTests: Foundation
!CreateTests: Markdown Preview
!CreateTests: File Tree
```

**Module name map:**

| Name you type | Source folder | Test output |
|---|---|---|
| Foundation | `2 Foundation/` | `2 Foundation/Tests/FoundationModuleTests.swift` |
| Terminal | `7 Terminal/` | `7 Terminal/Tests/TerminalModuleTests.swift` |
| Markdown Preview | `4 Markdown Preview/` | `4 Markdown Preview/Tests/MarkdownPreviewModuleTests.swift` |
| File Tree | `6 Project File Tree/` | `6 Project File Tree/Tests/FileTreeModuleTests.swift` |
| Text Editor | `3 Text Editor/` | `3 Text Editor/Tests/TextEditorModuleTests.swift` |
| PDF Viewer | `5 PDF Viewer/` | `5 PDF Viewer/Tests/PDFViewerModuleTests.swift` |
| HTML Preview | `8 HTML Preview/` | `8 HTML Preview/Tests/HTMLPreviewModuleTests.swift` |
| Resources | `9 Resources/` | `9 Resources/Tests/ResourcesModuleTests.swift` |

---

## When to invoke

- Bootstrapping test coverage for a new module (no tests exist yet)
- Expanding tests after adding significant new logic to a module
- Auditing what's testable vs. untestable in a module

---

## Inputs (confirm before starting)

| Input | Source |
|---|---|
| Module name | From user invocation |
| Module Guide | `1 Setup/Module Guides/<N> <Name>/` |
| Source code | `<N> <Name>/*.swift` |
| Existing tests (if any) | `<N> <Name>/Tests/<Module>Tests.swift` |

---

## Steps

### 1. Read context — REQUIRED BEFORE ANYTHING ELSE

Run in parallel:

- **`1 Setup/Vibe_Coding_Rules.md`** — internalize every rule; generated tests must comply
- **Module Guide** at `1 Setup/Module Guides/<N> <Name>/` — architecture, threading model, key types
- **All `.swift` source files** in the module folder
- **Existing test file** (if present) — read patterns, avoid duplicating tests
- **`1 Setup/References/Issues.md`** — note any open issues that affect testability

If the Module Guide is missing, stop and run `!CreateAModuleGuide` first.

---

### 2. Analyze the source code

For each `.swift` file, classify every public type:

| Category | Examples | Action |
|---|---|---|
| Pure logic (structs, enums, functions) | ANSIParser, SettingsStore, FileNode | **Test these** — highest ROI |
| @Observable state | AppState, TerminalSession | **Test state transitions** |
| Async entry points | PTY I/O, file watchers | **Test with async/await + @MainActor** |
| Protocol/interface | Mocking seams | **Create mock implementations** |
| UI-only code | NSViewRepresentable, SwiftUI views | **Skip and report** |
| AppKit delegate glue | NSTextDelegate, etc. | **Skip and report** |

Build an inventory table before writing any tests:

```
Type              | Category     | Testable? | Test count target
------------------|--------------|-----------|------------------
ANSIParser        | Pure logic   | Yes       | 20–30
TerminalEmulator  | Pure logic   | Yes       | 15–20
TerminalView      | UI (SwiftUI) | No        | —
```

---

### 3. Design the test suite

For each testable type, write tests in these categories:

**Happy path** — does the basic case work?
```swift
@Test func parserHandlesPlainText() {
    let parser = ANSIParser()
    let result = parser.parse("hello")
    #expect(result.text == "hello")
    #expect(result.attributes.isEmpty)
}
```

**Edge cases** — empty input, boundary values, maximum values
```swift
@Test func parserHandlesEmptyInput() {
    let parser = ANSIParser()
    let result = parser.parse("")
    #expect(result.text.isEmpty)
}
```

**Error conditions** — invalid input, graceful failure (never crash)
```swift
@Test func parserHandlesMalformedEscapeSequence() {
    let parser = ANSIParser()
    // Truncated escape — should not crash or throw
    let result = parser.parse("\u{1B}[")
    #expect(result.text.isEmpty)
}
```

**State transitions** — @Observable mutations are reflected correctly
```swift
@Test @MainActor func appStateTracksOpenDocument() async {
    let state = AppState()
    state.openDocument(url: URL(fileURLWithPath: "/tmp/test.md"))
    #expect(state.currentDocumentURL?.lastPathComponent == "test.md")
}
```

**Async methods** — use `async let` or `await` with `withCheckedContinuation`
```swift
@Test func fileWatcherDetectsNewFile() async throws {
    let watcher = FileSystemWatcher()
    let dir = FileManager.default.temporaryDirectory
    try await watcher.watch(directory: dir)
    // verify watcher started
    #expect(watcher.isWatching)
}
```

---

### 4. Write mock implementations

For each external dependency identified, create a minimal mock in the test file:

```swift
// MARK: - Mocks

final class MockPTYHandle: PTYHandleProtocol {
    var writtenData: [Data] = []
    var readHandler: ((Data) -> Void)?

    func write(_ data: Data) {
        writtenData.append(data)
    }

    func simulateInput(_ string: String) {
        readHandler?(Data(string.utf8))
    }
}
```

Rules for mocks:
- Mocks go at the **top** of the test file in a `// MARK: - Mocks` section
- Keep mocks minimal — only implement what the test actually calls
- Never mock types the module owns — only mock external dependencies (AppKit, file system, PTY)
- Prefer protocols as mocking seams; if no protocol exists, note it in the summary

---

### 5. Generate the test file

**File location:** `<N> ModuleName/Tests/<ModuleName>Tests.swift`

**File structure:**

```swift
// <ModuleName>ModuleTests.swift
// Generated by !CreateTests skill — review before merging

import Testing
@testable import Sputnik

// MARK: - Mocks
// (mock types here)

// MARK: - <TypeName>Tests

struct <TypeName>Tests {

    // MARK: Happy Path

    @Test func <descriptiveName>() { ... }

    // MARK: Edge Cases

    @Test func <descriptiveName>() { ... }

    // MARK: Error Conditions

    @Test func <descriptiveName>() { ... }
}

// MARK: - <NextTypeName>Tests

struct <NextTypeName>Tests {
    ...
}
```

**Naming conventions:**
- Test names start with the action being tested: `testParserHandles...`, `testStateTransitions...`
- Use `#expect(...)` not `XCTAssert...` — Swift Testing only
- Use `@Test` not `func test...` (the `@Test` macro is the entry point)
- Group by type using nested structs, not functions — one `struct <TypeName>Tests` per type
- `@MainActor` on the struct if all tests in it touch UI or @Observable state

**What to skip (and report):**
- SwiftUI views (`View`, `some View`)
- `NSViewRepresentable` wrappers
- AppKit delegate methods that have no logic of their own
- Anything that requires a real PTY, file system, or display server (flag for integration tests)

---

### 6. Check for existing tests

Before writing:
- If `<N> ModuleName/Tests/<Module>Tests.swift` exists → **read it first**, then append only new tests
- Do not duplicate existing test names
- Add a `// MARK: - Added by !CreateTests <date>` divider when appending

---

### 7. Write the test file

Write the complete test file to the target path. If appending to an existing file, insert after the last existing `@Test` function but before any closing braces.

---

### 8. Generate the summary report

Print a summary after writing the file:

```
## !CreateTests Summary: <Module Name>

### Tests written: <N>
| Category        | Count |
|---|---|
| Happy path      | N |
| Edge cases      | N |
| Error handling  | N |
| State mutation  | N |
| Async           | N |

### Types tested
- ✅ ANSIParser — 24 tests (state machine, escape sequences, color codes)
- ✅ TerminalEmulator — 18 tests (grid ops, cursor movement, scrollback)
- ⚠️  TerminalSession — 6 tests (lifecycle only; PTY I/O requires integration test)

### Skipped (untestable via unit tests)
- ❌ TerminalView — SwiftUI view; no testable logic
- ❌ PTYBridge — requires real PTY device (flag for integration tests)

### Estimated unit test coverage: ~65% of public API

### Manual tests still needed
1. PTY I/O with real shell process (TerminalSession)
2. ANSI color rendering on screen (TerminalView)
3. Scrollback performance under load (integration)

### To run tests
swift test --filter <ModuleName>
```

---

## Rules

- **No force-unwraps** in generated test code — use `#require(...)` or `guard let` in test setup
- **No file I/O, network, or sleep** in unit tests — mock those boundaries
- **No third-party test helpers** — Swift Testing stdlib only
- **Tests must compile on first attempt** — re-read the source type signatures before writing assertions
- **Each test has exactly one logical assertion** — prefer focused tests over multi-assertion tests
- If a Module Guide is missing for the target module, stop and run `!CreateAModuleGuide` first
- Log any issues found during analysis with `!TrackIssues` before continuing
- New tests are always placed in `<N> ModuleName/Tests/` — never inline in source files
