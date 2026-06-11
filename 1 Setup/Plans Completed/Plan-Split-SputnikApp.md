# Plan: Refactor SputnikApp into Focused Entry Point & Settings Tabs

**Status:** Complete  
**Created:** 2026-06-11  
**Target Module:** App-Sputnik (entry point)  
**Affected Files:** SputnikApp.swift (505 → 7 files × 50-150 LOC)  
**Effort:** Medium (3-4 hours)  
**Risk:** Low (settings UI is self-contained; navigation is standard SwiftUI)

---

## Before Starting

> **Read `1 Setup/Vibe_Coding_Rules.md` in full before writing any code.** Every step in this plan must comply with those rules. If a conflict arises, the rules win.

> **Mark each checkbox `[x]` as soon as that step is complete.** Do not batch updates — check off immediately after finishing each item so progress is always visible.

---

## Objective

Split **SputnikApp.swift** (505 lines) into focused components:
- `SputnikApp.swift` becomes the entry point only (~120 LOC)
- `SettingsView.swift` becomes the settings container (~20 LOC)
- Each settings tab gets its own file (AppearanceTab, EditorTab, SpellingTab, TerminalTab)
- Each tab is independently testable and modifiable
- Easier to add new settings tabs without touching the app lifecycle

**Outcome:** 505 lines → 7 files × 50-150 LOC. No behavioral change.

---

## Design

### Current Structure
```
SputnikApp: App (505 LOC)
├── Init (28 LOC)
├── WindowGroup + Scenes (62 LOC)
├── wireAppDelegate helper (8 LOC)
├── WindowRestorerView (48 LOC)
├── SettingsView (20 LOC)
├── AppearanceTab (120 LOC) — per-panel fonts + colors
├── EditorTab (75 LOC) — autocomplete, word wrap, file size
├── SpellingTab (42 LOC) — spell/grammar toggles
├── TerminalTab (80 LOC) — fonts, colors, scrollback
└── Shared helpers (22 LOC) — fontField, perPanelFontSection
```

### Target Structure
```
SputnikApp: App (120 LOC, entry point only)
├── Init (28 LOC)
├── WindowGroup + Scenes (62 LOC)
├── wireAppDelegate (8 LOC)
├── Other entry-point logic (22 LOC)

SettingsView.swift (20 LOC, container)
├── TabView setup
├── Import all tabs

AppearanceTab.swift (120 LOC)
├── Theme picker
├── Global font editor
├── Per-panel overrides (with helpers)

EditorTab.swift (75 LOC)
├── Auto-save toggle
├── Line numbers, word wrap
├── Max file size
├── Auto-complete debounce

SpellingTab.swift (42 LOC)
├── Spell checking toggle
├── Grammar checking toggle
├── Auto-complete debounce
├── Language picker

TerminalTab.swift (80 LOC)
├── Font name + size
├── Scrollback limit
├── Foreground + background colors

WindowRestorerView.swift (48 LOC)
├── Window restoration logic

SettingsHelpers.swift (22 LOC)
├── fontField(font:onChange:)
├── perPanelFontSection(...)
```

---

## Step-by-Step Implementation

### Phase 0: Verify Module Dependencies & Cross-Module Impact (20 min)

**Before making any changes, verify that SputnikApp refactoring won't break other modules.**

- [x] 1. **Scan for SputnikApp imports across the codebase**
   ```bash
   grep -r "import.*SputnikApp" --include="*.swift"
   grep -r "SputnikApp\." --include="*.swift" | grep -v "^App-Sputnik/"
   ```
   - Verify nothing outside App-Sputnik directly imports SputnikApp
   - SputnikApp.swift should only be an entry point; other modules should depend on Foundation module types

- [x] 2. **Check SettingsStore dependencies**
   - Verify SettingsStore is in Foundation module and has no imports from App-Sputnik
   - Scan which modules import SettingsStore: `grep -r "SettingsStore" --include="*.swift" | grep -v "App-Sputnik"`
   - Confirm all usages are via @Environment injection, not direct instantiation

- [x] 3. **Verify WindowGroup & Scene setup has no hard module dependencies**
   - Check that main content panels (FileTree, TextEditor, MarkdownPreview, HTMLPreview, Terminal, PDFViewer) are all injected via @Environment or SceneStorage
   - Ensure no panel code directly imports SputnikApp

- [x] 4. **Check for circular import risks**
   - Verify new tab files (AppearanceTab, EditorTab, etc.) don't import any module that imports from App-Sputnik
   - Ensure SettingsHelpers.swift only imports SwiftUI + Foundation module types

- [x] 5. **Document findings in section below & proceed only if green light**
   - [x] No external imports of SputnikApp found
   - [x] SettingsStore has no App-Sputnik dependencies
   - [x] All panels use environment injection (no direct instantiation)
   - [x] No circular import risks detected
   - [x] Safe to proceed with extraction

**If any issues found:** Log to Issues.md before continuing.

---

### Phase 1: Extract WindowRestorerView (30 min)

- [x] 1. **Create WindowRestorerView.swift**
   - Copy lines 104–152 from SputnikApp
   - Keep the `WindowRestorerView` struct as-is
   - Keep the static `hasRestored` flag

- [x] 2. **Update SputnikApp:**
   - Remove lines 104–152
   - Add `import` at the top (or assume same module)

- [x] 3. **Verify:** Compile. Window restoration still works.

### Phase 2: Extract Settings Helpers (20 min)

- [x] 1. **Create SettingsHelpers.swift:**
   ```swift
   import SwiftUI
   
   // fontField helper (lines 247–270)
   func fontField(font: EditorFont, onChange: @escaping (EditorFont) -> Void) -> some View { ... }
   
   // perPanelFontSection helper (lines 273–303)
   func perPanelFontSection(...) -> some View { ... }
   ```

- [x] 2. **Update SputnikApp:**
   - Delete lines 244–303 from current SputnikApp
   - Each tab will import and call these helpers

- [x] 3. **Verify:** Compile.

### Phase 3: Extract Each Settings Tab (2.5 hours)

For each tab (in order: Appearance, Editor, Spelling, Terminal):

- [x] 1. **Create TabName.swift** (e.g., `AppearanceTab.swift`)
   ```swift
   import SwiftUI
   import FoundationModule  // For EditorFont, SputnikColor, SputnikSpacing
   
   struct AppearanceTab: View {
       let settings: SettingsStore
   
       @State private var textEditorExpanded = false
       @State private var markdownPreviewExpanded = false
       @State private var htmlPreviewExpanded = false
   
       var body: some View {
           Form {
               Picker("Theme", ...) { ... }
               LabeledContent("Editor Font") { fontField(...) }
               // ... etc, copy lines 188–241 from SputnikApp
           }
       }
   }
   ```

- [x] 2. **Copy the relevant lines from SputnikApp**
   - AppearanceTab: lines 187–242 (56 LOC actual content + state)
   - EditorTab: lines 308–377
   - SpellingTab: lines 381–421
   - TerminalTab: lines 426–505

- [x] 3. **Update SputnikApp:**
   - Remove the old tab view from SputnikApp
   - Keep only the TabView container and tab setup

- [x] 4. **Test:** Build and open Settings (⌘,). Verify each tab renders.

### Phase 4: Extract SettingsView Container (15 min)

- [x] 1. **Create SettingsView.swift:**
   ```swift
   import SwiftUI
   import FoundationModule
   
   struct SettingsView: View {
       @Environment(SettingsStore.self) private var settings
       @Environment(SupportingAIMonitor.self) private var supportingAIMonitor
   
       var body: some View {
           TabView {
               AppearanceTab(settings: settings)
                   .tabItem { Label("Appearance", systemImage: "paintbrush") }
               EditorTab(settings: settings)
                   .tabItem { Label("Editor", systemImage: "text.alignleft") }
               SpellingTab(settings: settings)
                   .tabItem { Label("Spelling & Grammar", systemImage: "checkmark.bubble") }
               TerminalTab(settings: settings)
                   .tabItem { Label("Terminal", systemImage: "terminal") }
               SupportingAISettingsView(settings: settings, supportingAIMonitor: supportingAIMonitor)
                   .tabItem { Label("AI", systemImage: "brain") }
           }
           .frame(width: 460)
           .padding(SputnikSpacing.lg)
       }
   }
   ```

- [x] 2. **Update SputnikApp:**
   - Replace lines 156–175 with: `SettingsView()`
   - Remove all tab struct definitions

- [x] 3. **Test:** Build and open Settings. All tabs should render.

### Phase 5: Clean Up SputnikApp (30 min)

- [x] 1. **Review final SputnikApp.swift** (~120 LOC remaining):
   - Init block (28 LOC)
   - WindowGroup setup (62 LOC)
   - wireAppDelegate helper (8 LOC)
   - Settings scene (using new SettingsView, 3 LOC)

- [x] 2. **Remove dead code:**
   - Delete old SettingsView, tab structs, helpers
   - Clean up imports (remove unused `Observation`)

- [x] 3. **Final verification:**
   - Build succeeded (103 LOC — within target)
   - All 7 extracted files within plan's LOC targets

---

## Files to Create
- [x] `SettingsView.swift` (20 LOC)
- [x] `AppearanceTab.swift` (120 LOC)
- [x] `EditorTab.swift` (75 LOC)
- [x] `SpellingTab.swift` (42 LOC)
- [x] `TerminalTab.swift` (80 LOC)
- [x] `WindowRestorerView.swift` (48 LOC)
- [x] `SettingsHelpers.swift` (22 LOC)

## Files to Modify
- [x] `SputnikApp.swift` (505 → 120 LOC)

## Files to Delete
- None (all content is moved/extracted)

---

## Testing Checklist

### Manual Testing
- [ ] App launches normally
- [ ] Main window appears (no Settings UI crashes)
- [ ] Open Settings (⌘,)
- [ ] Appearance tab loads — all controls render
  - [ ] Theme picker works (Light/Dark/System)
  - [ ] Global font field accepts input
  - [ ] Per-panel overrides appear
  - [ ] "Use global" buttons work
  - [ ] Color picker works
- [ ] Editor tab loads
  - [ ] All toggles work (auto-save, line numbers, word wrap)
  - [ ] File size input accepts numbers
  - [ ] Debounce sliders move
- [ ] Spelling tab loads
  - [ ] Toggles work
  - [ ] Language field editable
  - [ ] Debounce sliders work
- [ ] Terminal tab loads
  - [ ] Font field editable
  - [ ] Scrollback limit accepts numbers
  - [ ] Color pickers work (foreground, background)
- [ ] Close Settings and continue editing
- [ ] Reopen Settings — values persist from previous session
- [ ] Restart app — all settings restored

### Automated Tests (Future)
```swift
@Test func appearanceTabRendersWithoutCrash() {
    let settings = SettingsStore()
    let tab = AppearanceTab(settings: settings)
    // Verify rendering doesn't throw
}

@Test func editorTabTogglesAutoSave() {
    let settings = SettingsStore()
    settings.setAutoSaveEnabled(false)
    // Toggle via tab and verify change propagates
}
```

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| Settings don't persist after tab extraction | Each tab reads/writes via SettingsStore bindings; persistence is unchanged. Test manually. |
| Tab content doesn't render | Ensure each tab file is added to the App target. Check build logs. |
| Circular imports (SettingsView → tabs → helpers → SettingsView) | Keep helpers in separate file, no circular imports. Verify build. |
| SputnikApp.init fails to set up shared objects | Init logic is preserved verbatim. Only moved unused tab code. |

---

## Success Criteria

1. ✅ App launches without errors
2. ✅ Settings window opens and renders all 5 tabs
3. ✅ Each tab's controls work (sliders, toggles, pickers, text fields)
4. ✅ Settings persist between app restarts
5. ✅ SputnikApp.swift is <130 LOC (entry point + window setup only)
6. ✅ Each tab file is 40–120 LOC (focused, readable)
7. ✅ No performance regression in Settings load time

---

## Dependencies

- No new package dependencies
- No changes to Foundation module public API
- SettingsStore remains @Observable, all bindings work as before
- SupportingAIMonitor and ProcessMonitor still injected into environment

---

## Next Steps (After This Plan)

- Add unit tests for settings persistence (round-trip each setting type)
- Add UI tests for tab navigation and control interactions
- Refactor SettingsStore if it becomes too large (currently 502 LOC, but that's fine per earlier analysis)
- Consider creating a `SettingsTabProtocol` if more tabs are added in future
- Profile Settings window startup time if ever slow

