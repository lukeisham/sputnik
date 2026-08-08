---
plan: Decompose AppState into focused concerns (SR-6)
module: 2 Foundation (2.2 Global State Management) + 2.10 Templates
created: 2026-06-16
completed: 2026-06-16
status: complete
related_issues: ISS-148
---

## Purpose

`AppState.swift` (499 lines) covers at least 8 distinct concerns beyond its core responsibility of window/document coordination. This plan extracts the largest clearly-separable concern — Templates — into its own type, and organizes the remainder into in-file extensions to group related pass-throughs, without changing any caller code.

## Success Condition

- A new `TemplateManager` type owns all template state and async operations. `AppState` exposes a single `templateManager` property.
- All 7 existing callers (`FileMenuGroup`, `MenuHelpers`, `ContentView`, `SputnikApp`, `TemplatesTab`, `TemplatePlaceholderSheet`, `TemplateStore`) continue to compile unchanged — migration is done via a computed-pass-through layer.
- The remaining `AppState` body is organized into `// MARK:` extension blocks: `WindowRegistry`, `ActiveWindowPassThroughs`, `ProcessingAndAIState`, `CommandRouting`, `CrashRecovery`, `WindowPersistence`, `PanelVisibility`, `DocumentLifecycle`.
- The project builds cleanly. All multi-window, scratchpad, minimap, recovery, and document operations work identically.
- `AppState` drops from 499 to ~380 lines.

## Risks

- **Template → Window coupling:** `AppState.openTemplateDocument` calls `activeWindow.openDocuments.append`. A `TemplateManager` cannot do this without a reference to `AppState` or `WindowState`. **Decision:** `TemplateManager` takes a weak delegate callback `onOpenDocument: ((String, String) -> Void)?`, and `AppState` sets this in its init to point at its own `openTemplateDocument`. This keeps the manager decoupled while routing the document-creation call back to the window manager.
- **Caller migration path:** To avoid updating 7 files simultaneously, `AppState` keeps computed pass-through properties and delegate methods for one release cycle. Callers continue to write `appState.availableTemplates` — these read from `appState.templateManager.availableTemplates`. When all callers are migrated, the pass-throughs can be deleted.
- **Scratchpad/minimap as thin pass-throughs:** These are ~3 lines each and delegate directly to `WindowState`. Extracting them would create a new file for 3 lines of code — not worth it. Instead they stay in `AppState` but are grouped under a `// MARK: - Scratchpad` extension to make the boundary clear.

---

## Step 1 — Create `TemplateManager.swift`

**File:** `2 Foundation/2.2 Global State Management/TemplateManager.swift` (new)

What:
An `@Observable` class owning all template-related state and async operations. Extract the following from `AppState`:

```swift
@Observable
@MainActor
public final class TemplateManager {
    public var availableTemplates: [TemplateRecord] = []
    public var templatePendingRequest: TemplatePendingRequest?
    public var templateError: SputnikAlert?

    /// Called when a template needs to be opened as a document.
    /// Signature: `(content: String, fileExtension: String) -> Void`
    public var onOpenDocument: ((String, String) -> Void)?

    public func refreshTemplates() async { ... }
    public func applyTemplateDirectory(_ url: URL?) async { ... }
    public func openTemplate(record: TemplateRecord) { ... }
    public func saveCurrentAsTemplate(name: String, content: String, fileExtension: String) async throws { ... }
    public func deleteTemplate(record: TemplateRecord) async throws { ... }
}
```

Key design decisions in the extracted methods:

- `openTemplate` — moves the template-content-reading + placeholder-checking logic here. When no placeholders exist, calls `onOpenDocument(content, fileExtension)`. When placeholders exist, sets `templatePendingRequest`.
- `saveCurrentAsTemplate` — now receives `content` and `fileExtension` as parameters instead of reading from `activeDocument`. The caller (`AppState` pass-through or any future caller) provides them.
- `deleteTemplate` — unchanged, purely async trashing.
- `openTemplateDocument` — **stays in `AppState`** because it directly manipulates `activeWindow.openDocuments`. It's wired as the `onOpenDocument` closure during `AppState.init`.

```
AppState.init:
    self.templateManager = TemplateManager()
    templateManager.onOpenDocument = { [weak self] content, ext in
        self?.openTemplateDocument(content: content, fileExtension: ext)
    }
```

Why:
Templates are the largest single feature embedded in `AppState` (~74 lines, 3 stored properties, 6 methods). They have their own async lifecycle, their own errors, and their own store (`TemplateStore`). Extracting them makes `TemplateManager` independently testable and removes the most egregious SR-6 violation.

---

## Step 2 — Add pass-through layer in `AppState`

**File:** `2 Foundation/2.2 Global State Management/AppState.swift`

What:
Add computed pass-through properties and methods from `AppState` to `TemplateManager`, so existing callers compile without changes:

```swift
// MARK: - Template management (delegates to templateManager)

public var availableTemplates: [TemplateRecord] {
    templateManager.availableTemplates
}

public var templatePendingRequest: TemplatePendingRequest? {
    get { templateManager.templatePendingRequest }
    set { templateManager.templatePendingRequest = newValue }
}

public var templateError: SputnikAlert? {
    get { templateManager.templateError }
    set { templateManager.templateError = newValue }
}

public func refreshTemplates() async {
    await templateManager.refreshTemplates()
}

public func applyTemplateDirectory(_ url: URL?) async {
    await templateManager.applyTemplateDirectory(url)
}

public func openTemplate(record: TemplateRecord) {
    templateManager.openTemplate(record: record)
}

@available(*, deprecated, message: "Use templateManager directly")
public func saveCurrentAsTemplate(name: String) async throws {
    guard let content = activeDocument?.text else { return }
    let ext = activeDocument?.fileType.defaultExtension ?? "txt"
    try await templateManager.saveCurrentAsTemplate(name: name, content: content, fileExtension: ext)
}

public func deleteTemplate(record: TemplateRecord) async throws {
    try await templateManager.deleteTemplate(record: record)
}
```

Add `public let templateManager = TemplateManager()` as a stored property in `AppState`, and wire the `onOpenDocument` closure in `init`.

The `saveCurrentAsTemplate` deprecated annotation is optional — can be removed if the team prefers to migrate callers immediately.

Why:
A pass-through layer means callers don't need to be touched in this step. The template logic moves to `TemplateManager` where it belongs, but the `AppState` API surface stays identical until a follow-up migration pass.

---

## Step 3 — Organize `AppState` into MARK extensions

**File:** `2 Foundation/2.2 Global State Management/AppState.swift`

What:
After removing the template block, group the remaining members under `// MARK:` extension boundaries. Create an internal `AppState+Extensions.swift` file in the same directory with these grouping sections. Each extension is placed in its own file for navigability:

| Extension file | Contents | Est. lines |
|---|---|---|
| `AppState+WindowRegistry.swift` | `orderedWindowIDs`, `windows`, `activeWindowID`, `activeWindow`, `createWindow`, `closeWindow`, `setActiveWindow` | ~55 |
| `AppState+WindowPassThroughs.swift` | `activeWorkspaceDirectory`, `openDocuments`, `activeDocumentID`, `activeDocument`, `currentlyOpenFile`, `currentlyOpenFileType`, `layout`, `recentFiles`, `editorScrollFraction`, `requestedHelpTarget`, `requestedHelpTopic` | ~50 |
| `AppState+ProcessingState.swift` | `isProcessing`, `beginProcessing`, `endProcessing`, `supportingAIUsage`, `mainAIState`, `isInteractionAvailable` | ~25 |
| `AppState+ScratchpadAndMinimap.swift` | `scratchpadVisible`, `scratchpadText`, `scratchpadDockedWidth`, `minimapVisible`, `toggleMinimap` | ~20 |
| `AppState+CommandRouting.swift` | `editorCommandHandler`, `pairedPreviewPrintAction`, `pairedPreviewSaveAsPDFAction`, `router`, `registerEditorCommandHandler` | ~25 |
| `AppState+CrashRecovery.swift` | `pendingRecoveryNames`, `clearRecovery` | ~10 |
| `AppState+WindowPersistence.swift` | `pendingWindowIDs`, `restoreWindows`, `flushViewStates`, `collectDescriptors`, `allTerminalManagers` | ~95 |
| `AppState+PanelVisibility.swift` | `hasColumn`, `toggleColumn`, `toggleTerminal`, `restoreDefaultLayout`, `focusEditor`, `focusReader` | ~40 |
| `AppState+DocumentLifecycle.swift` | `openDocument`, `newUntitledDocument`, `closeDocument`, `newTypedDocument`, `newFolder`, `moveDocument`, `noteRecentFile`, `clearRecentFiles` | ~65 |
| `AppState.swift` (main file) | `init`, the `templateManager` stored property, and the template pass-throughs | ~30 |

Each extension is a standard Swift extension block:

```swift
extension AppState {
    // MARK: - Window registry

    public private(set) var orderedWindowIDs: [UUID] { ... }
    // ...
}
```

Why:
Splitting into extensions preserves the `AppState` type as a single conceptual unit (all callers still use `appState.property`) while achieving SR-6's goal of one-responsibility-per-file at the source level. Each extension file is ~10–95 lines, focused, and independently navigable.

---

## Step 4 — Remove dead pass-throughs (follow-up)

**File:** Various (`FileMenuGroup.swift`, `MenuHelpers.swift`, `ContentView.swift`, `SputnikApp.swift`, `TemplatesTab.swift`)

What:
After the extraction is verified, submit a follow-up pass that migrates template callers from `appState.availableTemplates` / `appState.openTemplate(...)` etc. to `appState.templateManager.availableTemplates` / `appState.templateManager.openTemplate(...)`. Once all callers are migrated, delete the deprecated pass-throughs from `AppState`.

Why:
Keeping the pass-throughs indefinitely would mean `AppState` stays bloated. The pass-throughs are a migration aid, not a permanent design.

---

## Verification

1. `xcrun swift build` — full app build with zero errors.
2. Run the app and verify:
   - File > Open Template shows the template list.
   - Selecting a template with no placeholders opens a new document.
   - Selecting a template with placeholders shows the placeholder sheet.
   - File > Save as Template writes the file.
   - File > Remove Template trashes it.
   - Settings > Templates tab: changing the directory triggers a refresh.
3. Verify scratchpad, minimap, recovery, window creation/closing, and document operations all work identically.

---

## Implementation Notes (2026-06-16)

- **Steps 1–3 complete.** `TemplateManager.swift` created; `AppState` split into 9 `AppState+*.swift` extension files plus a slimmed main file. `xcrun swift build` → **Build complete!** with zero errors.
- **Deviation — stored properties stay in `AppState.swift`.** Swift forbids stored properties in extensions, so the proposed `WindowRegistry` / `ProcessingState` / `CrashRecovery` / `WindowPersistence` stored properties (`windows`, `orderedWindowIDs`, `activeWindowID`, `supportingAIUsage`, `editorCommandHandler`, paired-preview closures, `router`, `pendingRecoveryNames`, `pendingWindowIDs`) remain in the main file, grouped under `// MARK:` headers. Only computed accessors and methods moved to extensions.
- **Visibility relaxation.** `windows`, `orderedWindowIDs`, and `editorCommandHandler` changed from `public private(set)` to `public internal(set)` so the extension files (different source files in the same module) can mutate them.
- **Step 4 (caller migration + pass-through removal) deferred** as a separate follow-up, per the plan. The deprecated annotation on `saveCurrentAsTemplate(name:)` was omitted to keep `MenuHelpers` warning-free until that pass.
