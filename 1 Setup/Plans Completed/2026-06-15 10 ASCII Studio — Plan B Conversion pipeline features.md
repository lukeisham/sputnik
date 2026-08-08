---
plan: ASCII Studio — Plan B Conversion pipeline features
module: 10 ASCII Studio
created: 2026-06-15
status: pending
related_issues: ISS-129, ISS-130, ISS-131, ISS-132, ISS-133, ISS-134
depends_on: Plan A (ISS-120 Sobel fix should land before step B2)
---

## Purpose
Extend `ImageToASCIIConverter` with six new conversion capabilities — custom character ramps, composite luminance+edge overlay mode, a light-threshold/negative-space control, Bayer ordered dithering, a ramp preview swatch, and output-size presets for export — without touching the live canvas or breaking existing luminance/line-art workflows.

## Success Condition
- Typing a custom character string in the ramp TextField updates the canvas in real time with the correct character set.
- Switching to Composite mode blends luminance cells and edge-overlay cells visibly differently from either solo mode.
- Moving the light-threshold slider from 0.5 to 1.0 progressively replaces light cells with spaces, creating a clear depth effect.
- Selecting Bayer dithering produces a different pattern from Floyd-Steinberg with the same source image.
- The ramp swatch updates live as the character set changes and is readable at any ramp length from 1 to 20 characters.
- "Save as .txt → Small" exports at 32 columns; "Standard" at 72; "Large" at 120; the live canvas width slider is unchanged after each export.
- `swift build` (all targets) produces zero errors and zero warnings.

## Steps

- [x] B1. **Custom character ramp — `RampStyle.custom` + Settings UI (ISS-129)**
   What:
   1. Add `case custom` to `RampStyle` in `ImageToASCIIConverter.swift`. Update the `characters` computed property to return `Settings.customRampString.map { String($0) }` for `.custom`; fall back to the `.ascii` preset if `customRampString` is empty.
   2. Add `var customRampString: String = ""` to `Settings`.
   3. In `ASCIIStudioView`, add a `TextField("Custom ramp…", text: $settings.customRampString)` below the `Picker` for `RampStyle`. Show/hide the TextField with `.visible(settings.rampStyle == .custom)`.
   Why: The five hardcoded presets leave users unable to dial in character weight for specific images. A custom ramp unlocks precise density control.

- [x] B2. **Composite conversion mode — luminance + edge overlay (ISS-130)**
   What:
   1. Add `case composite` to `Mode` in `ImageToASCIIConverter.swift`.
   2. In `convert(image:settings:)`, for `.composite`: run the luminance pass as normal, then run `ASCIIEdgeDetector.detectEdges`, normalise intensity to 0…1, and for each cell where edge intensity exceeds a hardcoded overlay threshold (0.4) replace the luminance character with a border character drawn from the last 3 chars of the ramp.
   3. Add the Composite option to the Mode picker in `ASCIIStudioView`.
   Note: Depends on the two-channel Sobel fix from Plan A step 4. If Plan A is not yet merged, composite will fall back to luminance output only until the Sobel fix is in place.
   Why: Luminance alone loses fine structure; line-art alone loses fill. Composite makes portraits and icons crisp without losing tonal gradation.

- [x] B3. **Light-threshold / negative-space control (ISS-131)**
   What:
   1. Add `var lightThreshold: Double = 1.0` to `Settings` (range 0.5…1.0; default 1.0 = no threshold = current behaviour).
   2. In the luminance conversion loop, after computing the ramp index, check: if the pixel luminance > `lightThreshold`, output a space character instead of the ramp character.
   3. In `ASCIIStudioView`, add a `Slider(value: $settings.lightThreshold, in: 0.5...1.0)` labelled "Light threshold" inside `adjustmentsDisclosure`, with a `.help("Higher values preserve more light areas; lower values carve out more negative space")` tooltip.
   Why: Photographic subjects with white/light backgrounds produce dense ASCII fill where viewers expect blank space. A threshold control lets users punch out the background without inverting the whole image.

- [x] B4. **`DitherMode` enum — add Bayer 4×4 ordered dithering (ISS-132)**
   What:
   1. Replace `var dither: Bool` in `Settings` with `var ditherMode: DitherMode = .none`.
   2. Add `enum DitherMode: String, CaseIterable, Sendable { case none, floydSteinberg, bayer }`.
   3. Write `applyBayerDither(to pixels: inout [Double], width: Int, height: Int)` using the standard 4×4 Bayer matrix (threshold values 0…15 mapped to 0…1, added to each pixel before quantisation).
   4. Update `convert(image:settings:)` to branch on `settings.ditherMode`.
   5. Update all callers of `Settings` that set `dither:` — within the 10 ASCII Studio module only, since this is a module-internal API.
   6. In `ASCIIStudioView`, replace the existing `Toggle("Dithering", …)` with a `Picker` over `DitherMode.allCases`.
   Why: Floyd-Steinberg error-diffusion and Bayer ordered dithering produce visually distinct textures. Offering both gives users a stylistic choice. Replacing `dither: Bool` with an enum avoids a sprawl of future booleans.

- [x] B5. **Ramp preview swatch (ISS-133)**
   What:
   1. Create `RampSwatchView: View` in a new file `10 ASCII Studio/Sources/RampSwatchView.swift`. It takes a `[String]` characters array and renders them left-to-right over a `LinearGradient` from black to white, capped at 20 characters, each character in `Font.system(.body, design: .monospaced)`.
   2. Place `RampSwatchView(characters: settings.effectiveRamp)` directly below the ramp Picker in `ASCIIStudioView`. Update live as `rampStyle` or `customRampString` changes (SwiftUI reactivity handles this automatically).
   Why: Without a swatch, users cannot tell at a glance whether their selected or custom ramp is light-to-dark or dark-to-light, making brightness/contrast adjustments blind.

- [x] B6. **Output-size presets for Save as .txt (ISS-134)**
   What:
   1. Add `enum OutputPreset: String, CaseIterable { case small = "Small (32 cols)", standard = "Standard (72 cols)", large = "Large (120 cols)" }` with `var columns: Int { switch self { case .small: return 32; case .standard: return 72; case .large: return 120 } }`.
   2. In `ASCIIStudioView`, add a `Menu("Save as .txt…") { ForEach(OutputPreset.allCases) { preset in Button(preset.rawValue) { saveAtPreset(preset) } } }` button in the action bar alongside the existing "Save" button.
   3. Implement `saveAtPreset(_ preset: OutputPreset)`: a) create a local copy of `settings` with `targetColumns = preset.columns`; b) call `ImageToASCIIConverter.shared.convert(image: sourceImage, settings: localSettings)` — re-converting from the stored source image; c) write the result to disk via the existing `savePanel` flow with a filename suffix like `_32col.txt`; d) do NOT update `imageEditor` or any `@Published` property, so the live canvas is untouched.
   4. Store `private var sourceImage: NSImage?` in `ASCIIStudioView` and set it whenever a new image is imported or pasted, so `saveAtPreset` always has something to re-convert.
   Why: Users want to export at fixed column widths for specific contexts (icon-style vs body text vs large poster) without disturbing the canvas they are actively working on.

## Risks and Constraints
- **SR-1:** `ImageToASCIIConverter` is internal to module 10. All API changes (Settings, DitherMode, Mode) are within that module — no cross-module contract is broken.
- **SR-3:** Bayer dithering is a pure pixel-array pass over a Double buffer — no extra heap allocations beyond the existing luminance array. Composite runs two conversion passes per export; note this in a `// two-pass` comment but do not double-buffer unnecessarily.
- **`lightThreshold` default:** 1.0 means "no threshold applied" — all existing conversions are unchanged by default.
- **`dither: Bool` rename (B4):** this is a breaking API change within the module. A compile-time search for `dither:` in 10 ASCII Studio source files will locate all callers that need updating; expect at most 2–3 sites.
- **`sourceImage` storage (B6):** if the user has only loaded a `.txt` file (not an image), `sourceImage` is nil and the preset save must show an appropriate alert rather than crashing.

## Files Affected
- `10 ASCII Studio/Sources/ImageToASCIIConverter.swift` — steps B1, B2, B3, B4 (Settings, Mode, RampStyle, DitherMode, convert logic)
- `10 ASCII Studio/Sources/ASCIIStudioView.swift` — steps B1, B2, B3, B4, B5, B6 (UI controls and saveAtPreset)
- `10 ASCII Studio/Sources/RampSwatchView.swift` — step B5 (new file)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified
- [ ] Module Guide 10 updated: `status`, `last_updated`, new types documented (OutputPreset, DitherMode, RampSwatchView)
- [ ] Changes committed: `[10] ASCII Studio — Plan B Conversion pipeline features`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
