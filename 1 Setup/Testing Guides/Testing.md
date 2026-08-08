# Testing Guide — Sputnik

## Overview

Sputnik uses **Swift Testing** (not XCTest) for all unit tests. Tests live in a `Tests/` subfolder inside each module folder.

```
2 Foundation/
  Tests/
    FoundationModuleTests.swift
7 Terminal/
  Tests/
    TerminalModuleTests.swift
...
```

---

## Swift Testing Syntax

### Declaring a test

```swift
import Testing

@Test func myTest() {
    #expect(1 + 1 == 2)
}
```

### Grouping tests by type

```swift
struct ANSIParserTests {

    @Test func parsesPlainText() {
        let parser = ANSIParser()
        #expect(parser.parse("hello").text == "hello")
    }

    @Test func parsesResetSequence() {
        let parser = ANSIParser()
        _ = parser.parse("\u{1B}[0m")
        #expect(parser.currentAttributes == .default)
    }
}
```

### Async tests

```swift
@Test @MainActor func stateUpdatesAfterOpen() async {
    let state = AppState()
    await state.openDocument(url: testURL)
    #expect(state.currentDocumentURL == testURL)
}
```

### Require (fatal assertion — stops the test immediately)

```swift
@Test func parseReturnsNonNil() throws {
    let result = try #require(parser.parse("hello"))
    #expect(result.text == "hello")
}
```

### Parameterized tests

```swift
@Test(arguments: ["\u{1B}[31m", "\u{1B}[32m", "\u{1B}[33m"])
func parsesColorCode(sequence: String) {
    let result = ANSIParser().parse(sequence)
    #expect(result.attributes.foreground != nil)
}
```

---

## Running Tests

Run all tests:
```bash
swift test
```

Run tests for one module only:
```bash
swift test --filter Foundation
swift test --filter Terminal
```

Run a single test struct:
```bash
swift test --filter ANSIParserTests
```

Run a single test function:
```bash
swift test --filter "ANSIParserTests/parsesPlainText"
```

---

## Test Coverage by Module

| Module | Test file | Status |
|---|---|---|
| 2 Foundation | `2 Foundation/Tests/FoundationModuleTests.swift` | Partial |
| 3 Text Editor | `3 Text Editor/Tests/TextEditorModuleTests.swift` | Pending |
| 4 Markdown Preview | `4 Markdown Preview/Tests/MarkdownPreviewModuleTests.swift` | Pending |
| 5 PDF Viewer | `5 PDF Viewer/Tests/PDFViewerModuleTests.swift` | Pending |
| 6 Project File Tree | `6 Project File Tree/Tests/FileTreeModuleTests.swift` | Pending |
| 7 Terminal | `7 Terminal/Tests/TerminalModuleTests.swift` | Pending |
| 8 HTML Preview | `8 HTML Preview/Tests/HTMLPreviewModuleTests.swift` | Pending |
| 9 Resources | `9 Resources/Tests/ResourcesModuleTests.swift` | Pending |

Use `!CreateTests: <module-name>` to bootstrap test coverage for any pending module.

---

## Writing Tests by Hand

### What to test
- Pure-logic structs and enums (highest ROI)
- @Observable state transitions
- Async entry points
- Error handling (no crashes on bad input)

### What not to test
- SwiftUI `View` bodies
- `NSViewRepresentable` wrappers
- AppKit delegate methods with no logic

### Mock pattern

Protocols are the mocking seam. If a type that needs mocking has no protocol, add one:

```swift
// In source
protocol PTYHandleProtocol {
    func write(_ data: Data)
}

// In test file — MARK: - Mocks section
final class MockPTYHandle: PTYHandleProtocol {
    var writtenData: [Data] = []
    func write(_ data: Data) { writtenData.append(data) }
}
```

### Naming conventions

| Pattern | Example |
|---|---|
| Action + subject | `parsesEscapeSequence` |
| Condition + outcome | `emptyInputReturnsEmptyResult` |
| State + expected change | `openDocumentUpdatesCurrentURL` |

---

## Using !CreateTests

To auto-generate tests for a module:

```
!CreateTests: Terminal
```

The skill will:
1. Read the Module Guide and all source files
2. Identify testable types and logic
3. Write `<N> ModuleName/Tests/<Module>Tests.swift`
4. Print a coverage summary (what was tested, what was skipped, what needs manual tests)

See [`1 Setup/SKILLS/!CreateTests/skill.md`](../SKILLS/!CreateTests/skill.md) for full details.

---

## Best Practices

1. **One assertion per test** — keeps failures diagnostic, not ambiguous
2. **Descriptive names** — `parsesMultipleColorCodesInSequence` beats `test3`
3. **No sleeps** — use `await` with async APIs; never `Thread.sleep`
4. **No file I/O** — use in-memory strings and mock file handles
5. **No network** — always mock URLSession or equivalent
6. **@MainActor on the struct** when all tests touch UI or @Observable state — avoids per-test annotation clutter
7. **MARK: comments** — separate Happy Path / Edge Cases / Error Conditions within each struct
