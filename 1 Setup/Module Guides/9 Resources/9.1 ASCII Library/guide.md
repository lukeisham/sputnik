---
module: 9.1 Resources – ASCII Library
status: complete
last_updated: 2026-06-09
---

## Purpose
Provide a curated, searchable collection of ASCII art templates and line-art patterns that the Text Editor (3.3) can reference for block completion and ghost-text suggestions, and that the ASCII Art Help (9.2) can display as usage examples. No module reads raw ASCII art files directly — all access goes through the library's index.

## Diagram

```
                    Module 9.1 — ASCII Library
  ┌─────────────────────────────────────────────────────────┐
  │  ASCIILibrary (actor, backed by bundled ASCIILibrary.bundle) │
  │                                                         │
  │  Index (plist)  ─── fast prefix/lookup                  │
  │   ├── title: "Simple Cat"                               │
  │   ├── tags: [animal, cat, small]                        │
  │   ├── category: animals                                 │
  │   └── filename: "cat_simple.txt"                        │
  │                                                         │
  │  Art files (9 Resources/ASCIILibrary/)                  │
  │   ├── animals/cat_simple.txt                            │
  │   ├── animals/dog_big.txt                               │
  │   ├── borders/dashed.txt                                │
  │   ├── borders/single_line.txt                           │
   │   └── decorations/star_border.txt                       │
  └──────────┬──────────────────────────────────────┬───────┘
             │                                      │
             ▼                                      ▼
  Text Editor 3.3                         ASCII Art Help 9.2
  (block completion,                      ("Show in Library")
   ghost-text suggestions)
```

## Technical Summary
- **Framework(s):** Foundation (`Bundle`, `Codable`, `FileManager`), Swift Concurrency
- **Key types:**
  - `ASCIILibrary` — `actor` that loads and caches the art index on init; exposes `search(query: String) -> [ASCIIArtRecord]`, `art(id: UUID) -> String?`, and `categories() -> [String]`; lazy-loads the actual art file content from disk on first request (never loads all art into RAM at once, SR-3) <!-- assumed -->
  - `ASCIIArtRecord` — `Codable` value type: `id: UUID`, `title: String`, `tags: [String]`, `category: String`, `filename: String` (relative to the library root) <!-- assumed -->
  - `ASCIILibraryIndex` — `Codable` container wrapping an array of `ASCIIArtRecord`; loaded from `index.json` inside the library bundle <!-- assumed -->
- **Bundle layout:** Art lives in `9 Resources/ASCIILibrary/` as plain `.txt` files organised into subdirectories by category (`animals/`, `borders/`, `decorations/`, `objects/`, `people/`, etc.). An `index.json` at the root lists every piece with its metadata. The whole directory is packaged as `ASCIILibrary.bundle` at build time.
- **Threading model:** `ASCIILibrary` is an `actor` so all access is serialised. Index loading happens once on init. Art file content is fetched on the caller's `Task` (typically utility or user-initiated) and never held for longer than the caller needs it.
- **Data flow:**
  - Start-up: `ASCIILibrary.init()` loads `index.json` into memory (small, ~1 KB per 100 records) → caller asks `search(query:)` → index is filtered by title/tag prefix match → results returned as `[ASCIIArtRecord]` (no content loaded yet) → caller picks one → `art(id:)` reads the `.txt` file from disk and returns the string.
  - Editor integration (3.3): when the user types an art trigger (e.g. `:cat`), the editor queries `ASCIILibrary.search(query: "cat")` → shows the first 3 matches as ghost-text suggestions → if accepted, `ASCIILibrary.art(id:)` is called and the content is inserted.
  - Help integration (9.2): when the help viewer shows a category page, it fetches all art in that category via `ASCIILibrary.search(category: "animals")` and renders each record's content inline.
- **State owned:** The in-memory `[ASCIIArtRecord]` index (small). No art file content is cached persistently; each `art(id:)` call reads from disk.
- **Dependencies:** None within Sputnik — this is a leaf module. Foundation types (`Codable`, `UUID`, `Bundle`) only.
- **Failure modes:**
  - `index.json` missing or malformed → library loads empty; the editor gets no ghost-text suggestions; the help viewer shows an "ASCII Library not available" notice; no crash (SR-2).
  - Art `.txt` file missing from disk → `art(id:)` returns `nil`; caller (editor or help) handles the absence gracefully by showing nothing.
  - Very large index → still small (text metadata); but if it ever grows beyond 10 MB the index itself could be lazy-loaded in chunks — not needed for the foreseeable future.
  - Concurrent access → actor serialisation means safe by default; no data races.

## Spec Reference
> From the project structure: `9 Resources/` holds shared assets, including `ASCIILibrary` for ASCII art. The library is consumed by module 3.3 (ASCII art block completion/ghost text) and module 9.2 (ASCII Art Help).
