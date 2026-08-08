---
plan: RAM efficiency — off-thread file-tree scanning and bounded PDF thumbnail cache
modules: 5 PDF Viewer / 6 Project File Tree
created: 2026-06-13
status: pending
related_issues: ISS-104, ISS-105, ISS-106
---

## Purpose

Fix three low-RAM / fast-loading violations discovered in the RAM efficiency audit:

- **ISS-104** — `FileTreeViewModel` scans directories on the main thread despite claiming
  background dispatch (`Task(priority:)` inherits `@MainActor`).
- **ISS-105** — `PDFViewerViewModel.generateThumbnail` rasterises on the main thread for
  the same reason.
- **ISS-106** — `PDFViewerViewModel.thumbnailCache` is an unbounded plain dictionary; a
  10,000-page document can accumulate GBs of cached bitmaps.

These are the same `Task(priority:)` → `Task.detached` pattern fixed for `EditorViewModel`
in ISS-081 (plan "3 Editor concurrency and save-safety hardening"), applied to modules 5 and 6.

## Success Condition

- `swift build` clean across all packages — no new warnings in modules 5 or 6.
- Opening a directory with 1,000+ files (or a network mount) does not stall the UI — verified
  by Instruments Time Profiler showing `FileTreeViewModel.loadLevel` off the main thread
  (ISS-104).
- Scrolling the thumbnail sidebar through a 200-page PDF shows no perceptible main-thread
  stutter — `page.thumbnail(of:for:)` absent from the main-thread hot path in Instruments
  (ISS-105).
- After scrolling through all 200 pages, Instruments shows `thumbnailCache` entry count
  capped at ≤200 rather than growing unboundedly (ISS-106).
- Existing module-5 and module-6 tests (if any) continue to pass.

---

## Steps

### Step 1 — Fix file-tree scanning: replace `Task(priority:)` with `Task.detached` (ISS-104)

**File:** `6 Project File Tree/FileTreeViewModel.swift`

**What:** In `expandNode(_:)` (line 103) and `scanLevel(_:)` (line 270), replace:

```swift
// expandNode
let children = await Task(priority: .background) { FileTreeViewModel.loadLevel(id) }.value

// scanLevel
await Task(priority: .userInitiated) { FileTreeViewModel.loadLevel(url) }.value
```

with:

```swift
// expandNode
let children = await Task.detached(priority: .background) { FileTreeViewModel.loadLevel(id) }.value

// scanLevel
await Task.detached(priority: .userInitiated) { FileTreeViewModel.loadLevel(url) }.value
```

**Why:** `Task(priority:)` inherits the caller's actor (`@MainActor`), so `loadLevel` — a
`nonisolated static` that does disk I/O — runs on the main thread. `Task.detached` breaks
the isolation and runs on the cooperative pool. `loadLevel` is already `nonisolated static`
and captures nothing from `self`, so no snapshot is needed.

**Verify:** No other call sites in this file use `Task(priority:)` with `loadLevel`-style
work. `applyChildren` and tree mutations stay `@MainActor` (they run after `.value` is
awaited back on the main actor).

---

### Step 2 — Fix thumbnail rasterisation: replace `Task(priority:)` with `Task.detached` (ISS-105)

**File:** `5 PDF viewer/PDFViewerViewModel.swift`

**What:** In `generateThumbnail(for:)` (line 275), replace:

```swift
Task(priority: .background) { [weak self] in
    let size = CGSize(width: 120, height: 160)
    let image = page.thumbnail(of: size, for: .mediaBox)
    await MainActor.run {
        self?.thumbnailCache[pageIndex] = image
    }
}
```

with:

```swift
let capturedPage = page          // snapshot the PDFPage before leaving @MainActor
Task.detached(priority: .background) { [weak self] in
    let size = CGSize(width: 120, height: 160)
    let image = capturedPage.thumbnail(of: size, for: .mediaBox)
    await MainActor.run {
        self?.thumbnailCache.setObject(image, forKey: pageIndex as NSNumber)
    }
}
```

**Why:** `Task(priority:)` inherits `@MainActor`; `page.thumbnail(of:for:)` is real
rasterisation work. Detaching runs it on the cooperative pool. `PDFPage` is thread-safe for
read-only operations (thumbnail generation). After Step 3 the cache write uses `setObject`.

**Note:** `page` is captured from the guard-let above the Task in `generateThumbnail`, so
`capturedPage` is just a rename for clarity. Because the method is `@MainActor`, this
snapshot is safe — no data race.

---

### Step 3 — Replace unbounded dictionary with NSCache (ISS-106)

**File:** `5 PDF viewer/PDFViewerViewModel.swift`

**What:** Replace the `thumbnailCache` declaration and all its usage sites.

**3a. Change the declaration (line 69):**

```swift
// Before
public var thumbnailCache: [Int: NSImage] = [:]

// After
public let thumbnailCache = NSCache<NSNumber, NSImage>()
```

In `init()`, configure the cache limit:

```swift
public init() {
    thumbnailCache.countLimit = 200   // ~200 × ≈200 KB ≈ 40 MB peak
}
```

**3b. Update `loadPDF` and `loadImage` — clear on document change:**

```swift
// Before
thumbnailCache.removeAll()

// After
thumbnailCache.removeAllObjects()
```

**3c. Update `generateThumbnail` — check cache and write:**

```swift
// Before (guard)
guard thumbnailCache[pageIndex] == nil, ...

// After
guard thumbnailCache.object(forKey: pageIndex as NSNumber) == nil, ...

// Write (in the detached Task, from Step 2)
self?.thumbnailCache.setObject(image, forKey: pageIndex as NSNumber)
```

**3d. Update `ThumbnailsSidebarView` / `ThumbnailCell` — read from cache:**

`ThumbnailCell.thumbnailImage` currently reads `viewModel.thumbnailCache[index]`. Replace:

```swift
// Before
if let nsImage = viewModel.thumbnailCache[index] {

// After
if let nsImage = viewModel.thumbnailCache.object(forKey: index as NSNumber) {
```

**Why:** `NSCache` auto-evicts under memory pressure and respects `countLimit`. A 200-entry
cap limits peak usage to ≈40 MB of decoded bitmaps (200 × ~200 KB at 120×160 px), compared
to potentially GBs for a 10,000-page document with the current dictionary.

**Note:** `NSCache` is `public var` but `let` is sufficient since the object is mutated
(items added/removed) not replaced. Change `public var` → `public let`.

---

## Files Changed

| File | Change |
|---|---|
| `6 Project File Tree/FileTreeViewModel.swift` | `Task(priority:)` → `Task.detached(priority:)` in `expandNode` and `scanLevel` |
| `5 PDF viewer/PDFViewerViewModel.swift` | `Task(priority:)` → `Task.detached(priority:)` in `generateThumbnail`; `thumbnailCache` type changed to `NSCache`; `countLimit` set in `init`; read/write/clear calls updated |
| `5 PDF viewer/ThumbnailsSidebarView.swift` | `thumbnailCache[index]` → `thumbnailCache.object(forKey: index as NSNumber)` |

## Invariants Preserved

- All `@MainActor` state mutations still happen on the main actor (via `await MainActor.run`
  in the detached tasks, or after `.value` is awaited back).
- `loadLevel` remains `nonisolated static` — no change to its contract.
- `PDFPage.thumbnail(of:for:)` is documented as safe to call from any thread (read-only
  rasterisation into a new `NSImage`).
- `NSCache` is thread-safe; concurrent reads/writes from the detached task (write) and the
  main actor (read, via `ThumbnailCell`) are safe.
