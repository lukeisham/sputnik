# SPM Build Wire-Up Plan — Module-Per-Package
**Date:** 2026-06-09  
**Status:** New  
**Scope:** All modules (2–8), App Assembly, root Package.swift

---

## Goal

Structure the Sputnik source tree as seven local SPM library packages (one per module), assembled by a root `Package.swift` that defines the executable target. `swift build` at the project root compiles the full app with enforced module boundaries.

---

## Package Map

| Package name | Source path | Depends on |
|---|---|---|
| `FoundationModule` | `2 Foundation/` | *(none — base layer)* |
| `TextEditorModule` | `3 Text Editor/` | `FoundationModule` |
| `MarkdownPreviewModule` | `4 Markdown Preview/` | `FoundationModule`, `TextEditorModule` |
| `PDFViewerModule` | `5 PDF viewer/` | `FoundationModule` |
| `FileTreeModule` | `6 Project File Tree/` | `FoundationModule` |
| `TerminalModule` | `7 Terminal/` | `FoundationModule` |
| `HTMLPreviewModule` | `8 HTML Preview/` | `FoundationModule`, `TextEditorModule` |
| `SputnikApp` *(executable)* | `App-Sputnik/` | all 7 above |

---

## Task List

### T-1 — Delete the three existing `Packages/` stubs

**Files to delete:** `Packages/CoreSputnik/`, `Packages/UIComponentsSputnik/`, `Packages/NetworkingSputnik/`  
**Why:** These stubs don't map to any module and are not imported anywhere in the main app. Leaving them creates a confusing parallel package hierarchy.  
**How:** `rm -rf Packages/CoreSputnik Packages/UIComponentsSputnik Packages/NetworkingSputnik` — then delete the empty `Packages/` directory if nothing else lives there.  
**Effort:** 2 min.

---

### T-2 — Add a `Package.swift` to each module folder

Each module folder gets a minimal `Package.swift`. The pattern is identical across all seven — only the name, path, and `dependencies:` list differ.

**Template:**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "<ModuleName>",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "<ModuleName>", targets: ["<ModuleName>"])
    ],
    dependencies: [
        // list sibling packages here, e.g.:
        // .package(name: "FoundationModule", path: "../2 Foundation"),
    ],
    targets: [
        .target(
            name: "<ModuleName>",
            dependencies: [ /* mirror the package dependencies above */ ],
            path: "."  // all .swift files in the folder, recursively
        )
    ]
)
```

**Seven files to create:**

| File | Name | Dependencies |
|---|---|---|
| `2 Foundation/Package.swift` | `FoundationModule` | *(none)* |
| `3 Text Editor/Package.swift` | `TextEditorModule` | `FoundationModule` |
| `4 Markdown Preview/Package.swift` | `MarkdownPreviewModule` | `FoundationModule`, `TextEditorModule` |
| `5 PDF viewer/Package.swift` | `PDFViewerModule` | `FoundationModule` |
| `6 Project File Tree/Package.swift` | `FileTreeModule` | `FoundationModule` |
| `7 Terminal/Package.swift` | `TerminalModule` | `FoundationModule` |
| `8 HTML Preview/Package.swift` | `HTMLPreviewModule` | `FoundationModule`, `TextEditorModule` |

**Important:** Each `Package.swift` must live at the *root* of the module folder (not inside a subfolder). SPM resolves sources recursively from that root, so all `.swift` files in subdirectories are picked up automatically.

---

### T-3 — Create the root `Package.swift`

**File:** `/Users/lukeishammacbookair/Developer/App_Sputnik/Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SputnikApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "FoundationModule",       path: "2 Foundation"),
        .package(name: "TextEditorModule",       path: "3 Text Editor"),
        .package(name: "MarkdownPreviewModule",  path: "4 Markdown Preview"),
        .package(name: "PDFViewerModule",        path: "5 PDF viewer"),
        .package(name: "FileTreeModule",         path: "6 Project File Tree"),
        .package(name: "TerminalModule",         path: "7 Terminal"),
        .package(name: "HTMLPreviewModule",      path: "8 HTML Preview"),
    ],
    targets: [
        .executableTarget(
            name: "SputnikApp",
            dependencies: [
                "FoundationModule",
                "TextEditorModule",
                "MarkdownPreviewModule",
                "PDFViewerModule",
                "FileTreeModule",
                "TerminalModule",
                "HTMLPreviewModule",
            ],
            path: "App-Sputnik"
        )
    ]
)
```

The `App-Sputnik/` folder currently holds only `Assets.xcassets`. It will also need the `@main` entry point (see T-7 below).

---

### T-4 — Access control audit (largest task)

SPM enforces module boundaries: any type, `init`, method, or property used *outside* the package it is defined in **must be `public`**. This is the main hidden cost of the packages approach.

**Audit process — per module:**

1. Run `swift build` from the project root after T-3.
2. Collect every `error: ... is internal` or `error: initializer is inaccessible` diagnostic.
3. Add `public` to each flagged declaration.
4. Repeat until clean.

**Known `public` already in place (from reading the code):**
- `ContentView` — `public struct` ✓  
- `InterPanelRouter` — `public protocol` ✓  
- `AppState` — check; likely needs `public` on all stored properties  
- `DocumentSession`, `PanelEvent`, `FileType`, `PanelPosition` — check each

**High-risk files (cross-module surface area):**
- `2 Foundation/2.2 Global State Management/AppState.swift` — consumed by every other module
- `2 Foundation/2.4 UI and UX/DesignTokens.swift` — `SputnikColor`, `SputnikFont` used everywhere
- `2 Foundation/2.1 Inter-Panel communication/PanelEvent.swift` — used by router subscribers
- `3 Text Editor/3.1 Text/EditorView.swift` — consumed by `ContentView` (in `SputnikApp`)
- `7 Terminal/TerminalView.swift` — consumed by `ContentView`

**Rule of thumb:** if a type is referenced by name in a file that lives in a *different* numbered folder, its declaration and all `init`s must be `public`.

---

### T-5 — Wire `EditorView` into `ContentView`

**File:** `App-Sputnik/ContentView.swift` (move `ContentView` here, or keep in `FoundationModule` and add `import TextEditorModule`)  
**Current placeholder:** line 52 — `slotPlaceholder(position: .centerUpper, color: .green.opacity(0.10))`  
**Replace with:** `EditorView()`

**Steps:**
1. Add `import TextEditorModule` at the top of `ContentView.swift`.
2. Confirm `EditorView.init()` is `public`.
3. Replace line 52 with `EditorView()`.
4. Run `swift build` — fix any access-control errors surfaced.

---

### T-6 — Wire `TerminalView` into `ContentView`

**File:** `App-Sputnik/ContentView.swift` (or `2 Foundation/2.6 App Lifecycle/ContentView.swift`)  
**Current placeholder:** `terminalPlaceholder` computed var (lines 135–144)  
**Replace with:** `TerminalView()`

**Steps:**
1. Add `import TerminalModule`.
2. Confirm `TerminalView.init()` and `TerminalManager` are `public`.
3. Replace `terminalPlaceholder` body with `TerminalView()`.
4. Confirm PTY lifecycle (`TerminalLifecycle.swift` in Foundation) is triggered at app startup — it must run before `TerminalView` appears.

---

### T-7 — Create `AppInterPanelRouter` and wire it

**New file:** `2 Foundation/2.1 Inter-Panel communication/AppInterPanelRouter.swift`

**Skeleton:**

```swift
import Foundation

@MainActor
public final class AppInterPanelRouter: InterPanelRouter {

    public let events: AsyncStream<PanelEvent>
    private let continuation: AsyncStream<PanelEvent>.Continuation

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    public func open(_ file: URL) async {
        // 1. classify FileType from extension
        // 2. find-or-create DocumentSession in AppState
        // 3. emit .fileOpened event via continuation
    }

    public func close(_ id: UUID) async {
        // 1. check isDirty → show SputnikAlert if needed
        // 2. remove session from AppState.openDocuments
        // 3. update activeDocumentID
        // 4. emit .fileClosed event
    }

    public func syncDirectory(_ url: URL) {
        // update AppState.activeWorkspaceDirectory
        // emit .directoryChanged
    }
}
```

**Wire-up in `SputnikApp.swift`:**
- Instantiate `AppInterPanelRouter` as `@State private var router = AppInterPanelRouter()`.
- Pass via environment or direct injection to `ContentView`.
- Update `ContentView`'s tab-close closure to call `router.close(id)`.
- Wire `FileTreeModule` file-selection callback → `router.open(_:)`.
- Wire `TerminalModule` directory-change callback → `router.syncDirectory(_:)`.

---

### T-8 — Move `ContentView` to `App-Sputnik/` (app assembly layer)

**Why:** `ContentView` imports from `TextEditorModule` and `TerminalModule`. If it stays inside `FoundationModule`, Foundation gains a dependency on those modules — breaking the one-way dependency rule (Foundation must not depend on any peer module).

**Steps:**
1. Move `2 Foundation/2.6 App Lifecycle/ContentView.swift` → `App-Sputnik/ContentView.swift`.
2. Add the necessary imports (`FoundationModule`, `TextEditorModule`, `TerminalModule`, etc.) at the top of the moved file.
3. Remove the file from `FoundationModule`'s source tree.
4. Update `SputnikApp.swift` (also in `App-Sputnik/`) if it references `ContentView` — the import will now resolve from the same target, no `import` statement needed.

---

### T-9 — Create `Info.plist`

**File:** `App-Sputnik/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Sputnik</string>
    <key>CFBundleIdentifier</key>      <string>com.lukeisham.sputnik</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleExecutable</key>      <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
```

---

### T-10 — Create entitlements file

**File:** `App-Sputnik/Sputnik.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
```

---

## Execution Order

```
T-1   Delete Packages/ stubs
T-2   Add Package.swift to each of the 7 module folders
T-3   Create root Package.swift
        → swift build  (expect many access-control errors — that's normal)
T-4   Access control audit — fix all public/internal errors
        → swift build  (should be clean after this)
T-8   Move ContentView to App-Sputnik/
        → swift build
T-5   Wire EditorView into ContentView
        → swift build
T-6   Wire TerminalView into ContentView
        → swift build
T-7   Implement AppInterPanelRouter + wire into SputnikApp
        → swift build
T-9   Create Info.plist
T-10  Create entitlements
```

Run `swift build` after each step so errors stay isolated to the change just made.

---

## Issues to Log

- `ISS-NEW-A`: No concrete `InterPanelRouter` implementation — routing is non-functional (T-7).
- `ISS-NEW-B`: `EditorView` and `TerminalView` are not wired — placeholders shown at launch (T-5, T-6).
- `ISS-NEW-C`: `ContentView` lives inside `FoundationModule`, creating a hidden upward dependency once editor/terminal imports are added (T-8).
