# Plan: Create "Create Tests" Skill for Sputnik Modules

**Status:** New  
**Created:** 2026-06-11  
**Target Module:** Testing infrastructure (cross-module)  
**Affected:** All modules (2 Foundation through 9 Resources)  
**Effort:** High (1-2 weeks of agent work to bootstrap all modules)  
**Risk:** Medium (requires understanding each module's architecture and dependencies)

---

## Objective

Create a reusable AI agent **skill** (Claude prompt) that:
1. **Reads** a module's code and architecture (via Module Guide)
2. **Generates** unit tests for core logic (not UI where possible)
3. **Creates** mock implementations for dependencies
4. **Structures** tests using Swift Testing framework (not XCTest)
5. **Saves** tests to `Module/Tests/ModuleTests.swift`
6. **Returns** a summary of test coverage and what's untestable

**Outcome:** A skill that can be invoked as:
```
/create-tests <module-name>
```

This will automatically generate 20–50 tests per module, reducing manual test writing by 70%.

---

## Design

### What the Skill Does

**Input:**
- Module name (e.g., "Terminal", "Markdown Preview", "PDF Viewer")
- Module Guide path (e.g., `1 Setup/Module Guides/7 Terminal/`)
- Source code paths (e.g., `7 Terminal/*.swift`)

**Process:**
1. Read the Module Guide to understand:
   - Purpose (one-sentence description)
   - Public API (what can be tested)
   - Key dependencies (what needs mocking)
   - Algorithms (where tests have most value)

2. Analyze the source code:
   - Identify pure-logic functions/structs
   - Identify `@Observable` state and state transitions
   - Identify async entry points
   - Flag what's UI-only and untestable

3. Generate tests:
   - Happy path (basic functionality)
   - Edge cases (empty inputs, boundary values)
   - Error conditions (graceful failure)
   - State transitions (async updates reflected in @Observable)
   - Mocking dependencies (using TestingSupport)

4. Output:
   - Tests file (ModuleTests.swift)
   - Summary report (coverage %, untestable areas, manual tests needed)

---

### Modules to Test (Priority Order)

| Module | Priority | Test Count | Key Logic |
|---|---|---|---|
| **2 Foundation** | ⭐ Highest | 40–50 | AppState lifecycle, SettingsStore persistence, MainAIMonitor detection |
| **7 Terminal** | ⭐ Highest | 50–70 | ANSIParser (escape sequences), TerminalEmulator (grid ops), PTY lifecycle |
| **4 Markdown Preview** | ⭐ High | 25–35 | Rendering logic, scroll sync coordination |
| **6 File Tree** | ⭐ High | 20–30 | FileSystemWatcher, node hierarchy, drag-and-drop validation |
| **3 Text Editor** | Medium | 20–30 | Auto-save debounce, line numbering, word wrap |
| **5 PDF Viewer** | Medium | 15–25 | Outline extraction, page navigation, zoom constraints |
| **8 HTML Preview** | Medium | 15–20 | Link policy, image scheme handler, injection safety |
| **9 Resources** | Low | 15–20 | ASCII library lookup, help index loading |

---

## Skill Prompt Structure

The skill will be invoked by Claude Code with a prompt like:

```
/create-tests Terminal

Instructions:
- Read 1 Setup/Module Guides/7 Terminal/
- Read 7 Terminal/*.swift
- Read 2 Foundation/Tests/FoundationModuleTests.swift (for test patterns)
- Generate 50-70 tests for Terminal module
- Focus on ANSIParser (state machine, escape sequences), TerminalEmulator (grid operations)
- Create mocks for PTYHandle, TerminalSession dependencies
- Output: 7 Terminal/Tests/TerminalModuleTests.swift
- Return a summary of:
  * Test count and categories
  * Coverage estimate
  * Untestable areas (why)
  * Next steps (integration tests, manual tests)
```

### Skill Prompt (Pseudo-code)

```markdown
# Create Tests for Sputnik Module

## Input
Module name: {module_name}
Module path: {module_path}
Module guide: {guide_path}

## Instructions

1. **Read Module Guide**
   - Understand purpose, architecture, key classes/structs
   - Identify public APIs and testable entry points
   - Note dependencies and threading model

2. **Analyze Source Code**
   - List all public types (struct, class, enum, protocol)
   - Identify pure-logic functions (candidates for unit tests)
   - Identify @Observable state and its transitions
   - Identify async methods and task creation
   - Flag UI-only code (NSViewRepresentable, SwiftUI views)

3. **Design Tests**
   - For each testable type, write 3–10 tests:
     * Happy path (basic functionality)
     * Edge cases (empty, nil, boundary values)
     * Error cases (graceful failure)
     * State mutations (async updates)
   - Use Swift Testing framework (@Test, #expect)
   - Create mocks for external dependencies
   - Use @MainActor context where needed

4. **Generate Test File**
   - Location: `{module_path}/Tests/{ModuleName}Tests.swift`
   - Structure: Group tests by type (@Test struct for MockRouterTests, etc.)
   - Import @testable module and TestingSupport
   - Include MARK: comments for organization

5. **Generate Summary Report**
   - Test count by category (logic, state, async, error handling)
   - Coverage estimate (% of public API)
   - Untestable areas and why (UI frameworks, FFI)
   - Next steps (integration tests, manual tests needed)

## Output

1. Tests file (Swift code, ready to compile)
2. Summary report (text)
3. Coverage checklist (types tested vs. skipped)
4. Notes (tricky areas, future improvements)
```

---

## Implementation Plan

### Phase 1: Create the Skill Prompt (1 day)

1. **Draft master prompt** (refined version of above):
   - Detailed instructions for analyzing module architecture
   - Test patterns for @Observable, async/await, mocking
   - Swift Testing syntax examples
   - Error handling patterns

2. **Store skill** in `1 Setup/SKILLS/!CreateTests.md`:
   ```markdown
   # Skill: !CreateTests
   
   Generates unit tests for a Sputnik module using Swift Testing.
   
   ## Usage
   !CreateTests: <module-name>
   
   Example:
   !CreateTests: Terminal
   
   ## What it does
   - Reads module architecture from Module Guide
   - Analyzes source code for testable logic
   - Generates 20-70 unit tests per module
   - Creates mocks for dependencies
   - Outputs test file + coverage report
   
   [Full prompt body...]
   ```

3. **Test the skill manually:**
   - Invoke on Foundation module (already has tests)
   - Verify generated tests compile and pass
   - Refine prompt based on output quality

### Phase 2: Verify Skill on Existing Tests (1 day)

1. **Run skill on Foundation module:**
   - Skill reads existing FoundationModuleTests.swift
   - Skill generates tests for MainAIMonitor, AppState, SettingsStore
   - Compare to existing tests for patterns

2. **Adjust skill prompt** if:
   - Generated tests are too verbose or too sparse
   - Test names don't match Sputnik conventions
   - Mocks don't align with TestingSupport patterns

3. **Verify output compiles:**
   ```bash
   cd App_Sputnik/2\ Foundation
   swift test
   ```

### Phase 3: Run Skill on Terminal Module (2-3 days)

1. **Run skill on Terminal:**
   ```
   /create-tests Terminal
   ```

2. **Review output:**
   - Check ANSIParser tests (should have 20–30 tests for state machine)
   - Check TerminalEmulator tests (grid operations, cursor movement)
   - Check TerminalSession tests (PTY lifecycle, I/O handling)

3. **Manual cleanup:**
   - Fix any import errors
   - Adjust mock implementations if needed
   - Verify tests pass

4. **Commit as baseline** (reference for future skill iterations):
   ```bash
   git add "7 Terminal/Tests/TerminalModuleTests.swift"
   git commit -m "Generate Terminal module tests via !CreateTests skill"
   ```

### Phase 4: Run Skill on Remaining Modules (4-5 days)

1. **High-priority modules** (2-3 days):
   - Foundation (append to existing tests)
   - File Tree (new tests)
   - Markdown Preview (new tests)

2. **Medium-priority modules** (1-2 days):
   - Text Editor
   - PDF Viewer
   - HTML Preview

3. **Low-priority modules** (1 day):
   - Resources

4. **Manual review & adjustment:**
   - Ensure all tests compile
   - Run full test suite: `swift test`
   - Fix any failures (usually mocking issues)

### Phase 5: Documentation & Integration (1 day)

1. **Update CLAUDE.md:**
   - Add !CreateTests to skill list
   - Document when to use (adding new module, expanding test coverage)

2. **Update README.md:**
   - Mention testing framework (Swift Testing)
   - Link to TestingSupport module
   - Testing roadmap

3. **Create testing guide:**
   - `1 Setup/Guides/Testing.md`
   - Best practices for Sputnik tests
   - How to run tests
   - How to write custom tests (for areas skill can't cover)

---

## Skill Success Criteria

### Output Quality
- [ ] Generated tests compile without errors
- [ ] All tests pass (no false positives)
- [ ] Test coverage includes happy path + edge cases + errors
- [ ] Test names are descriptive (e.g., `testAppStateClosesDocumentAndNotifiesObservers`)
- [ ] Mocks are simple and focused

### Usability
- [ ] Skill can be invoked via `/create-tests <module>`
- [ ] Output includes summary report (what was tested, what wasn't)
- [ ] Report explains untestable areas (e.g., "MarkdownRenderView is SwiftUI, skipped")
- [ ] Manual instructions are clear (how to run tests, where to customize)

### Coverage
- [ ] All public APIs have at least one test
- [ ] Core logic (parsing, state machines) has 3–10 tests
- [ ] Async methods tested with @MainActor context
- [ ] @Observable state mutations verified

### Maintainability
- [ ] Tests grouped by type (MockRouterTests, AppStateTests, etc.)
- [ ] MARK: comments separate sections
- [ ] Comments explain non-obvious test logic
- [ ] Easy to add more tests manually (test patterns are clear)

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| Skill generates untestable UI code | Skill analyzes code, skips NSViewRepresentable and pure SwiftUI views, reports what's skipped. |
| Skill doesn't understand module architecture | Skill reads Module Guide (designed for this purpose). If guide is missing, skill fails gracefully. |
| Generated tests are too simple (no real validation) | Skill includes edge cases and error handling. Manual review catches overly simple tests. |
| Skill creates duplicate tests (Foundation already has tests) | Skill checks for existing test file, appends or alerts. |
| Tests are slow or flaky | Skill avoids file I/O, network I/O, sleeps. Uses mocks and deterministic assertions. |

---

## Testing the Skill Itself

Once implemented, test the skill on:

1. **Foundation module** (most complex):
   - Verify MainAIMonitor tests (detection logic)
   - Verify AppState tests (window lifecycle)
   - Verify SettingsStore tests (persistence)

2. **Terminal module** (highest test ROI):
   - Verify ANSIParser tests (20–30 escape sequence tests)
   - Verify TerminalEmulator tests (grid ops)
   - Compare to hand-written tests (if any exist)

3. **File Tree module** (medium complexity):
   - Verify FileSystemWatcher tests
   - Verify node hierarchy tests

---

## Success Metrics

- **Lines of test code written:** 2,000–3,000 (via skill)
- **Manual test-writing time saved:** ~40 hours (1 week of work)
- **Modules with test coverage:** 8/8 (100%)
- **Public API coverage:** 80%+ of testable code
- **Test execution time:** <10 seconds (full suite)
- **Test reliability:** 100% (no flaky tests)

---

## Dependencies

- **Existing:** Swift Testing framework, TestingSupport module, Module Guides
- **New:** None

---

## Next Steps (After This Plan)

1. **Integration testing:**
   - UI tests for each module (future, not this plan)
   - Performance tests for Terminal emulator and file watcher
   - Crash tests (memory pressure, large files, edge cases)

2. **Continuous improvement:**
   - Run skill regularly when new modules added
   - Expand coverage as new features added
   - Create skill for UI/integration tests (future)

3. **Documentation:**
   - Add testing chapter to project guide
   - Create "test cookbook" (patterns for common scenarios)
   - Link to TestingSupport module docs

