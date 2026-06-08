# Sputnik — Claude Code Project Guide

## What Is Sputnik?

Sputnik is a native macOS development environment that coordinates six concurrent views — a Project File Tree, a Text Editor (Text, Markdown, ASCII art and HTML), a Markdown preview synchronized to the editor, a PDF viewer, a HTML preview also synchronized to the editor, and an integrated Zsh Terminal — within a unified, crash-resistant, memory-efficient minimalist layout, with interactive help guides. (Markdown, ASCII art, Grammar and HTML)

---

## Project Structure

```
App_Sputnik/
├── claude.md                      ← This file (project root, auto-loaded)
├── readme.md                      ← App spec and module breakdown
├── 2 Foundation/ … 8 HTML Preview/ ← Swift source folders (one per module)
├── 9 Resources/                   ← Shared assets (e.g. ASCIILibrary for ASCII art)
├── 1 Setup/
│   ├── Vibe_Coding_Rules.md       ← Coding rules (Sputnik + Swift + macOS)
│   ├── Module Guides/             ← One folder per module (2–8)
│   │   ├── 2 Foundation/
│   │   ├── 3 Text Editor Window/
│   │   ├── 4 Markdown Preview/
│   │   ├── 5 PDF Viewer/
│   │   ├── 6 Project File Tree/
│   │   ├── 7 Terminal/
│   │   └── 8 HTML Preview/
│   ├── SKILLS/                    ← Agent skill prompts (empty dirs = pending)
│   │   ├── !GrillMeWithContext
│   │   ├── !GenerateAPlan
│   │   ├── !TrackIssues
│   │   └── !CreateAModuleGuide
│   ├── References/
│   │   └── Issues.md              ← Known issues log
│   ├── Plans Completed/
│   └── Plans New/
```

---

## Coding Rules

### Sputnik Rules
1. **Modular design** — each module is self-contained; changes in one must not silently break another.
2. **Error and crash proof** — handle all failure paths explicitly; no force-unwraps in production paths.
3. **Low RAM usage** — lazy-load, stream large files, never hold more in memory than needed.
4. **Fast and efficient** — UI thread stays clear; heavy work goes off-thread.
5. **Use existing macOS frameworks** — prefer Apple's built-in APIs over third-party dependencies.

### Swift Rules
1. Use modern Swift Concurrency (`async/await`, `Task`, `AsyncStream`) over completion handlers.
2. Strict memory management: always audit for retain cycles; use `[weak self]` inside escaping closures.
3. Use **SwiftUI** for declarative layout; drop to **AppKit via `NSViewRepresentable`** only where raw macOS performance demands it (terminal rendering, heavy text views).

### macOS Framework Rules
| Need | Framework / API |
|---|---|
| PDF rendering | **PDFKit** |
| File system access & watching | **FileManager**, **FilePresenter** |
| Background work, QoS | **Grand Central Dispatch (GCD)** |
| Shell process spawning | **Foundation `Process`** — bind stdio to the PTY `FileHandle`, **not** a `Pipe` (see MR-4/MR-5) |
| PTY bridge for Zsh I/O | **`posix_openpt`, `grantpt`, `unlockpt`** |

---

## Module Map

| # | Module | Key responsibility |
|---|---|---|
| 2 | Foundation | Inter-panel comms, global state, settings, persistence, app lifecycle, UI/UX primitives |
| 3 | Text Editor Window | Text/Markdown/HTML/ASCII editing, syntax highlight, auto-save |
| 4 | Markdown Preview | Live-rendered Markdown preview, synced to editor |
| 5 | PDF Viewer | PDFKit rendering, TOC sidebar, thumbnails |
| 6 | Project File Tree | Folder tree, file operations, drag-and-drop |
| 7 | Terminal | PTY-hosted Zsh, ANSI rendering, scrollback |
| 8 | HTML Preview | Live HTML preview, synced to editor |
| 9 | Resources | Help guides for HTML, Markdown, Grammar and ASCII art plus the ASCII library |

Each module has a **Module Guide** in `1 Setup/Module Guides/<N> <Name>/`. See [Module Guide Format](#module-guide-format) below.

---

## Agent Skills

Invoke these by name at the start of a prompt. Skill prompt files live in `1 Setup/SKILLS/`.

| Skill | When to use |
|---|---|
| **!GrillMeWithContext** | Start here when the intent is unclear. Ask targeted questions to determine whether the user wants a plan, a refactor, a bug fix, or an explanation — then route accordingly. |
| **!GenerateAPlan** | Read the relevant Module Guide(s) and Vibe Coding Rules, invoke !TrackIssues if issues are found, update the Module Guide, save a plan to `Plans New/`, mark it complete when done. |
| **!TrackIssues** | Log new bugs, regressions, or design problems to `References/Issues.md` with a short description and the affected module. |
| **!CreateAModuleGuide** | Scaffold a new Module Guide file using the standard format (see below). |

---

## Module Guide Format

Every Module Guide must contain:

```markdown
---
module: <number and name>
status: draft | active | complete
---

## Purpose
One-sentence statement of what this module does.

## Appearance / Function Diagram
ASCII diagram showing the visual layout or call flow.

## Technical Summary
- Bullet-point list of key implementation details
- Framework used, data flow, threading model, key classes/structs
```

---

## Working Conventions

- **Read the Module Guide before touching a module.** It is the source of truth for that module's design intent.
- **One module at a time.** Cross-module changes require a plan first.
- **No force-unwraps** (`!`) in non-test code. Use `guard let` or `if let`.
- **No third-party Swift packages** unless explicitly approved — check `Vibe_Coding_Rules.md` first.
- **Issue first, fix second.** If you spot a problem while doing something else, log it with !TrackIssues before continuing.
- **Plans live in `Plans New/`** until the work is merged/complete, then move to `Plans Completed/`.
