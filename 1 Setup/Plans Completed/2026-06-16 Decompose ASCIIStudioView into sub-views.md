---
plan: Decompose ASCIIStudioView into three focused sub-views
module: 10 ASCII Studio
created: 2026-06-16
status: pending
related_issues: ISS-138
---

## Purpose

Decompose `ASCIIStudioView.swift` (695 lines, 25 `@State` properties, three distinct sub-domains) into separate files honouring SR-6 (one responsibility per file), while preserving all existing behaviour.

## Success Condition

- `ASCIIStudioView.swift` is a thin coordinator (~120 lines) that owns the shared model and switches between two tab views.
- `ASCIIStudioImageView.swift` contains the Image → ASCII conversion tab (controls, canvas, editing tools, file actions).
- `ASCIIStudioLibraryView.swift` contains the Library tab (search, category picker, clip grid).
- `ASCIIStudioModel.swift` is an `@Observable` class holding all shared state extracted from the 25 `@State` properties.
- The project builds cleanly. All import/export/edit/insert/clipboard actions work identically to before.

## Risks

- **StateObject migration:** `imageEditor` is currently `@StateObject private var imageEditor = ASCIIImageEditor()`. Moving it into the model would require `@ObservationIgnored` + manual init, risking lifecycle bugs. **Decision:** keep `imageEditor` as `@StateObject` in the coordinator and pass it as a binding to sub-views.
- **Alert bindings:** `showDiscardWarning`, `showNoImageAlert`, and `pendingAction` are tied to `.alert()` modifiers on the top-level view. `.alert()` modifiers must be on the view that presents them, so these stay in the coordinator.
- **Library constant:** `private let library = ASCIILibraryBrowser()` is not `@State`, so it stays in the coordinator and is passed as immutable to the library view.

---

## Step 1 — Create `ASCIIStudioModel.swift`

**File:** `10 ASCII Studio/Sources/ASCIIStudioModel.swift` (new)

What:
Create an `@Observable` class holding all mutable state currently spread across 25 `@State` properties in `ASCIIStudioView`. The full property list:

```swift
@Observable
public final class ASCIIStudioModel {
    var selectedTab: Tab = .imageToASCII
    var selectedImage: NSImage? = nil
    var asciiPreview: String = ""
    var isConverting: Bool = false
    var targetWidth: Double = 80
    var invert: Bool = false
    var rampStyle: ImageToASCIIConverter.RampStyle = .block
    var customRampString: String = ""
    var conversionMode: ImageToASCIIConverter.Mode = .luminance
    var brightness: Double = 0.0
    var contrast: Double = 1.0
    var ditherMode: ImageToASCIIConverter.DitherMode = .none
    var edgeStyle: ASCIIEdgeDetector.EdgeStyle = .simple
    var lightThreshold: Double = 1.0
    var adjustmentsExpanded: Bool = false
    var selectedCategory: ASCIILibraryBrowser.Category = .frames
    var showEditTools: Bool = false
    var replaceChar: String = ""
    var fillChar: String = ""
    var insertChar: String = " "
    var librarySearchQuery: String = ""
    var sourceImageName: String = ""
    var hasKnownEditor: Bool = false
    var showDiscardWarning: Bool = false
    var pendingAction: (() -> Void)? = nil
    var showNoImageAlert: Bool = false
    let library = ASCIILibraryBrowser()
}
```

`Tab` and `OutputPreset` are `enum` types nested inside `ASCIIStudioView` currently — move `Tab` to the model file (as a standalone enum) and keep `OutputPreset` in the coordinator (it's only used by `saveAtPreset`).

Why:
Centralising state in an `@Observable` model lets sub-views read/write without prop drilling and without each needing their own `@State`. This is the same pattern used by `EditorViewModel` in module 3.

---

## Step 2 — Create `ASCIIStudioImageView.swift`

**File:** `10 ASCII Studio/Sources/ASCIIStudioImageView.swift` (new)

What:
A `struct ASCIIStudioImageView: View` that receives the shared model (`ASCIIStudioModel`) and the image editor (`ASCIIImageEditor` via `@ObservedObject`) as parameters. This file carries everything from the Image → ASCII tab:

| Current member | Destination |
|---|---|
| `var imageTab: some View` | Top-level body of the sub-view |
| `var actionBar: some View` | Import/Open/Save/Insert/Copy button row |
| `var alwaysVisibleControls: some View` | Width slider, invert, ramp picker, mode/dither/edge pickers |
| `var adjustmentsDisclosure: some View` | Brightness/contrast/threshold expandable section |
| `var editToolbar: some View` | Selection, replace, align, fill, undo/redo toolbar |
| `var canvasArea: some View` | Preview/editing toggle + scrollable canvas |
| `var editableCanvas: some View` | `MonoGridView` + insert-character row |
| `func importImage()` | Opens NSOpenPanel for image files |
| `func openTXT()` | Opens ASCII file via `ASCIIExporter.open()` |
| `func saveToTXT()` | Saves canvas to .txt |
| `func saveAtPreset(_:)` | One-click preset-width export |
| `func regenerateOnChange()` | Regenerate with discard-warning |
| `func checkBeforeAction(_:)` | Guard before discarding edits |
| `func regenerate()` | Run `ImageToASCIIConverter.convert` in a Task |
| `func insertASCII(_:)` | Insert into editor via `ASCIIStudioCoordinator` |
| `func copyToClipboard()` | Copy canvas to pasteboard |
| `var effectiveRamp: [String]` | Resolved ramp character array |

The two `.alert()` modifiers stay in the coordinator (see Risks). The sub-view signals discards by setting `model.showDiscardWarning = true` and writing the continuation closure into `model.pendingAction`.

Why:
This is ~80 % of the original file's code. Extracting it leaves the coordinator and library view trivially small, and gives the conversion logic a clear home.

---

## Step 3 — Create `ASCIIStudioLibraryView.swift`

**File:** `10 ASCII Studio/Sources/ASCIIStudioLibraryView.swift` (new)

What:
A `struct ASCIIStudioLibraryView: View` that receives the model and the `ASCIILibraryBrowser` as parameters. This file carries:

| Current member | Destination |
|---|---|
| `var libraryTab: some View` | Top-level body — search, category picker, clip grid |
| `var clipCard(_:): some View` | Individual clip card with name, preview, insert button |
| `var filteredLibraryClips: [ASCIILibraryBrowser.Clip]` | Search/category filtered clip list |

```swift
struct ASCIIStudioLibraryView: View {
    @Bindable var model: ASCIIStudioModel
    let library: ASCIILibraryBrowser

    var body: some View {
        // search bar, category picker, clip grid
    }
}
```

Why:
The library tab is entirely self-contained — it reads/writes `selectedCategory`, `librarySearchQuery`, and the `library` constant, and inserts selected clips via `ASCIIStudioCoordinator.insertAtCursor`. Isolating it makes the library browsable and searchable without pulling in conversion logic.

---

## Step 4 — Rewrite `ASCIIStudioView.swift`

**File:** `10 ASCII Studio/Sources/ASCIIStudioView.swift` (rewrite)

What:
Replace the current 695-line file with a thin coordinator:

```swift
public struct ASCIIStudioView: View {
    @State private var model = ASCIIStudioModel()
    @StateObject private var imageEditor = ASCIIImageEditor()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.selectedTab) {
                ForEach(Tab.allCases, id: \.rawValue) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            Divider()

            Group {
                switch model.selectedTab {
                case .imageToASCII:
                    ASCIIStudioImageView(model: model, imageEditor: imageEditor)
                case .library:
                    ASCIIStudioLibraryView(model: model, library: model.library)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 400)
        .task { /* first-responder tracking */ }
        .alert("Discard Edits?", isPresented: $model.showDiscardWarning) { /* ... */ }
        .alert("No Source Image", isPresented: $model.showNoImageAlert) { /* ... */ }
    }
}
```

The `Tab` enum is replaced by a reference to the standalone `Tab` type now defined in `ASCIIStudioModel.swift`. The `OutputPreset` enum stays here (only used by the coordinator's `saveAtPreset` delegation).

The `init()` and the coordinator's `body` together should be ~25 lines. The two alert modifiers are ~20 lines each. The `.task` is ~10 lines. **Total: ~90 lines.**

Delete all private members that are now in the sub-views. After the rewrite, verify that no dead code remains.

Why:
The coordinator's only job is to own the model + imageEditor lifecycle and switch between the two tab views. Everything else is delegated to the sub-views.

---

## Verification

1. `xcrun swift build --target ASCIIStudioModule` — must compile with zero errors.
2. `xcrun swift build` — full app build must succeed.
3. Manual smoke-test the Studio panel:
   - Open an image, adjust settings (width, invert, ramp, dither, edge, brightness/contrast), re-convert.
   - Toggle edit mode, edit grid cells (replace, align, fill, insert).
   - Open library tab, search, filter by category, insert a clip.
   - Save to .txt, copy to clipboard, insert into editor.
   - Verify discard-warning appears when re-converting with manual edits.
   - Verify "No Source Image" alert appears when exporting preset with no image loaded.
