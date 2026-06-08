---
module: <N.N Module Name>
status: draft
last_updated: <YYYY-MM-DD>
---

<!--
  HOW TO USE
  - Copy this file to: 1 Setup/Module Guides/<N Module Name>/<N.N Sub-module Name>/guide.md
  - Fill every section — do not leave placeholders
  - Mark any assumed content (no source code yet) with <!-- assumed -->
  - status must be "draft" on creation; only !GenerateAPlan promotes it to "active"

  REQUIRED READS BEFORE WRITING THIS GUIDE:
  1. readme.md  — extract the spec bullets for this module
  2. 1 Setup/Vibe_Coding_Rules.md — note rules that apply to this module

  EDITING THIS FILE:
  - Claude: use built-in file editing tools
  - Any other agent: use Python to read and write .md files

    from pathlib import Path
    p = Path("path/to/guide.md")
    p.write_text(p.read_text().replace(old, new))
-->

## Purpose
<One sentence: what this module does and why it exists in Sputnik.>

## Diagram
<!--
  Use ASCII art showing ONE of:
  - UI layout:   panels and labels drawn with box-drawing characters (┌─┐│└┘)
  - Data flow:   boxes connected with arrows showing how data moves through the module
  No images, no Mermaid, no LaTeX.
-->

```
<ASCII diagram here>
```

## Technical Summary
- **Framework(s):** <e.g. PDFKit, SwiftUI, AppKit — list all used>
- **Key types:** <ClassName / StructName — one-liner on each>
- **Threading model:** <what runs on the main thread vs background; which GCD queues or Tasks are used>
- **Data flow:** <how data enters, transforms, and exits this module>
- **State owned:** <what @State / @Observable / actor this module controls>
- **Dependencies:** <which other modules or Foundation types this module calls into>
- **Failure modes:** <what can go wrong and how each case is handled>

## Spec Reference
> Extracted verbatim from `readme.md`:

```
<paste the relevant spec bullet points here — do not paraphrase>
```
