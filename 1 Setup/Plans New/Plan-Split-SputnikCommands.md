# Plan: Refactor SputnikCommands into Modular Menu System

**Status:** New  
**Created:** 2026-06-11  
**Target Module:** 2 Foundation / 2.0 App Overview  
**Affected Files:** SputnikCommands.swift (571 → 7 files × 50-100 LOC)  
**Effort:** Medium (3-4 hours)  
**Risk:** Low (menus are isolated; easy to verify against macOS menu bar)

---

## Objective

Split **SputnikCommands.swift** (571 lines) into focused menu modules:
- Each menu gets its own file (FileMenu, EditMenu, ViewMenu, etc.)
- Core `SputnikCommands` becomes a thin router (~80 lines)
- Each menu tests independently
- Easier to add/modify menu items without touching 10 other menus

**Outcome:** 571 lines → 17 files × 40-100 LOC. No behavioral change.

---

## Design

### Current Structure
```
SputnikCommands: Commands (571 LOC)
├── sputnikMenu          (~40)
├── fileMenu             (~100)
├── editMenu             (~90)
├── writingAssistanceMenu (~40)
├── formatMenu           (~15)
├── viewMenu             (~70)
├── windowMenu           (~60)
├── helpMenu             (~40)
└── helpers              (~37)
```

### Target Structure
```
SputnikCommands: Commands (80 LOC, router only)
├── sputnikMenuGroup (40 LOC)
├── fileMenuGroup (100 LOC)
├── editMenuGroup (90 LOC)
├── writingAssistanceMenuGroup (40 LOC)
├── formatMenuGroup (15 LOC)
├── viewMenuGroup (70 LOC)
├── windowMenuGroup (60 LOC)
├── helpMenuGroup (40 LOC)
└── MenuHelpers.swift (37 LOC)
```

---

## Step-by-Step Implementation

### Phase 0: Verify Module Dependencies & Cross-Module Impact (20 min)

**Before making any changes, verify that SputnikCommands refactoring won't break other modules.**

1. **Scan for SputnikCommands imports across the codebase**
   ```bash
   grep -r "import.*SputnikCommands" --include="*.swift"
   grep -r "SputnikCommands\." --include="*.swift" | grep -v "^2 Foundation/"
   ```
   - Verify SputnikCommands is only imported in App-Sputnik (as the entry point)
   - No panels or other modules should directly reference menu actions

2. **Check AppState, SettingsStore, AppInterPanelRouter dependencies**
   - Verify these types exist in Foundation module with correct signatures
   - Scan which modules use each: `grep -r "AppInterPanelRouter" --include="*.swift"`
   - Ensure all three are already injected/available to menu groups

3. **Verify menu helper functions have no external dependencies**
   - Check `openDocument()`, `saveAs()`, `presentAlert()` usage across codebase
   - Ensure they're internal to SputnikCommands (not called from other modules)
   - `grep -r "openDocument\|saveAs\|presentAlert" --include="*.swift" | grep -v "SputnikCommands"`
   - If found outside SputnikCommands, these functions must remain in SputnikCommands, not extracted

4. **Check for panel actions that might conflict with menu commands**
   - Verify panels don't define their own ⌘S, ⌘O, ⌘N handlers that would conflict
   - `grep -r "keyboardShortcut.*\\(\"s\"\\|\"o\"\\|\"n\"\\)" --include="*.swift" | grep -v "SputnikCommands"`
   - Ensure menu command dispatch is the single source of truth

5. **Verify AppInterPanelRouter can broadcast to all panels**
   - Check that router has methods for: file operations, view toggles, focus changes
   - Confirm no panel directly listens for menu broadcasts (should go through router only)

6. **Document findings & proceed only if green light**
   - [ ] SputnikCommands imported only from App-Sputnik
   - [ ] All dependencies (AppState, SettingsStore, AppInterPanelRouter) available
   - [ ] Helper functions not called from outside SputnikCommands
   - [ ] No menu shortcut conflicts in panel code
   - [ ] Router can broadcast to all affected panels
   - [ ] Safe to proceed with extraction

**If any issues found:** Log to Issues.md before continuing.

---

### Phase 1: Extract Helpers (30 min)
1. Create **MenuHelpers.swift**:
   - Extract `openDocument()` (lines 534–543)
   - Extract `saveAs()` (lines 545–561)
   - Extract `presentAlert(_:)` (lines 563–570)
   - Make private functions internal for the new menu modules

2. **Verify:** Compile. SputnikCommands still runs unchanged.

### Phase 2: Extract Each Menu (3 hours)
For each menu (in order: Sputnik, File, Edit, Spelling/Grammar, Format, View, Window, Help):

1. **Create MenuGroup.swift** (e.g., `FileMenuGroup.swift`)
   ```swift
   import AppKit
   import SwiftUI
   import FoundationModule
   
   struct FileMenuGroup {
       private let appState: AppState
       private let settingsStore: SettingsStore
       private let router: AppInterPanelRouter
       @Environment(\.openWindow) private var openWindow
       
       init(appState: AppState, settingsStore: SettingsStore, router: AppInterPanelRouter) {
           self.appState = appState
           self.settingsStore = settingsStore
           self.router = router
       }
       
       var body: some Commands {
           // Copy lines 75–178 from SputnikCommands
           Group {
               CommandGroup(replacing: .newItem) { ... }
               CommandMenu("File") { ... }
           }
       }
   }
   ```

2. **Update SputnikCommands** to call the new group:
   ```swift
   public var body: some Commands {
       SputnikMenuGroup(appState: appState, ...)
       FileMenuGroup(appState: appState, ...)
       // ... etc
   }
   ```

3. **Run** and verify menu bar is unchanged.

4. **Delete** the old inline menu from SputnikCommands.

### Phase 3: Test & Cleanup (30 min)
1. Build and run app
2. Click each menu (Sputnik, File, Edit, Format, View, Window, Help)
3. Verify all keyboard shortcuts work (⌘N, ⌘S, ⌘⌥A, etc.)
4. Check "Merge All Windows" action (complex, line 451–482)
5. Delete old commented code

---

## Files to Create
- `SputnikMenuGroup.swift` (40 LOC)
- `FileMenuGroup.swift` (100 LOC)
- `EditMenuGroup.swift` (90 LOC)
- `WritingAssistanceMenuGroup.swift` (40 LOC)
- `FormatMenuGroup.swift` (15 LOC)
- `ViewMenuGroup.swift` (70 LOC)
- `WindowMenuGroup.swift` (60 LOC)
- `HelpMenuGroup.swift` (40 LOC)
- `MenuHelpers.swift` (37 LOC)

## Files to Modify
- `SputnikCommands.swift` (571 → 80 LOC)

## Files to Delete
- None (old SputnikCommands is rewritten in place)

---

## Testing Checklist

### Manual Testing
- [ ] App launches (no crashes in menu setup)
- [ ] File → New Tab (⌘T)
- [ ] File → New Window (⌘⇧N)
- [ ] File → Open (⌘O)
- [ ] File → Save (⌘S)
- [ ] File → Save As (⌘⇧S)
- [ ] File → Render as HTML (⌘⌥P)
- [ ] Edit → Undo/Redo (⌘Z, ⌘⇧Z)
- [ ] Edit → Cut/Copy/Paste (⌘X, ⌘C, ⌘V)
- [ ] Edit → Find (⌘F)
- [ ] View → Toggle File Tree (⌘⌥1)
- [ ] View → Toggle Preview (⌘⌥2)
- [ ] View → Focus: Editor (⌘⌃E)
- [ ] Window → Minimize (⌘M)
- [ ] Window → Merge All Windows
- [ ] Help → Sputnik Help (⌘?)

### Automated Tests (Future)
Once writing tests, create:
```swift
@Test func fileMenuHasAllActions() {
    // Verify FileMenuGroup exposes expected buttons
}

@Test func keyboardShortcutsAreWired() {
    // Check ⌘T, ⌘S, etc. are bound
}
```

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| Menu doesn't appear in macOS menu bar | Each group extends `Commands`; SwiftUI composition is automatic. Test each group's `body`. |
| Keyboard shortcuts broken | Double-check `.keyboardShortcut()` modifiers in each group. Test manually. |
| Commands body doesn't render | Ensure each menu group returns `some Commands`, not a `View`. |

---

## Success Criteria

1. ✅ App launches without menu-related errors
2. ✅ All 7 menus render in macOS menu bar (File, Edit, View, Format, Window, Help, Sputnik)
3. ✅ All keyboard shortcuts work as before
4. ✅ "Merge All Windows" action executes without crashes
5. ✅ No performance regression in menu rendering
6. ✅ SputnikCommands file is <100 LOC (pure router)

---

## Dependencies

- No new package dependencies
- No changes to Foundation module public API
- Compatible with existing AppState, SettingsStore, AppInterPanelRouter

---

## Next Steps (After This Plan)

- Add unit tests for menu structure (verify groups aren't empty)
- Add integration tests for actions (File → Save actually saves)
- Consider extracting menu constants (key combos, labels) to a `MenuConstants.swift` enum
- Profile menu rendering time if app ever gets slow at startup (unlikely)

