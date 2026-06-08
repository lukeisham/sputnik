# Example: Header Design

A well-designed section header gives your document rhythm. It tells the reader "something new begins here" and establishes a visual pattern they can follow throughout the page. This tutorial demonstrates how to compose a polished header by combining three ASCII Library elements — a decorative top border, a framed title, and a bottom divider — into a single, cohesive block.

## The Anatomy of a Header

A complete ASCII header has three layers:

1. **Top accent** — an optional decorative row that introduces the header with personality.
2. **Title frame** — the section name, enclosed in a box for prominence.
3. **Bottom divider** — a horizontal rule that separates the header from the body text below.

```ascii
* . * . * . * . * . * . *       ← top accent (decorative pattern)
╔════════════════════════╗
║     SECTION TITLE      ║       ← title frame (double-line box)
╚════════════════════════╝
──────────────────────────       ← bottom divider (single line)
```

Each layer plays a distinct role. The top accent sets the tone; the frame anchors the reader's attention; the divider signals "the header is done, content follows."

## Step 1: Choose Your Tone

Before drawing a single character, decide how formal or playful the header should be. The tone determines every subsequent choice:

| Tone | Top Accent | Frame | Divider |
|------|-----------|-------|---------|
| **Professional** | None or subtle wave | Single or double line | Single line |
| **Bold & authoritative** | Star border | Double or thick line | Double line |
| **Friendly & creative** | Heart row or floral | Rounded | Star or dashed |
| **Celebratory** | Star border | Shadow box | Star divider |

For this example, we'll build a **bold section header** suitable for a README or project document.

## Step 2: Build the Top Accent

Start with the decorative pattern. The star border from the Decorative collection adds energy without sacrificing professionalism:

```ascii
* . * . * . * . * . * . * . *
```

@{art:deco-001}

Extend or trim the pattern to match your intended header width. For a 30-character-wide header, use exactly 30 characters of the star border pattern. If the pattern repeat doesn't divide evenly into your target width, trim the last repeat — a slightly asymmetrical end is less noticeable than a header whose layers have different widths.

## Step 3: Frame the Title

The title lives inside a double-line box. Position the title text in the center of the frame with one space of padding on each side:

```ascii
╔══════════════════════════════╗
║      GETTING STARTED         ║
╚══════════════════════════════╝
```

To center the title, count the available interior width (total box width minus 2 for the vertical edges), subtract the title length, and split the remainder into left and right padding. If the remainder is odd, put the extra space on the right. For example, a 30-character box has 28 interior columns. A 15-character title like `GETTING STARTED` leaves 13 spaces of padding — 6 on the left, 7 on the right.

> **Tip:** Use the ASCII Library's frame pieces as starting templates. Insert a frame, measure its interior width, type your title, then adjust the padding manually.

## Step 4: Add the Bottom Divider

The divider closes the header and creates a clean transition to body text. Match the divider's width to the frame above it:

```ascii
────────────────────────────────
```

@{art:div-001}

A single-line divider works well here because the double-line frame already provides enough visual weight. If you used a single-line frame, consider a double-line divider to balance the overall weight. If you used a thick-line frame, a double-line divider maintains the bold aesthetic.

## Step 5: Assemble and Adjust

Stack the three layers with one blank line between them so each component breathes:

```ascii
* . * . * . * . * . * . * . * . *

╔══════════════════════════════════╗
║         GETTING STARTED          ║
╚══════════════════════════════════╝

────────────────────────────────────

Body text begins here, after one blank line below the divider...
```

Leave exactly one blank line between the divider and the body text. If the body text also starts with a heading (e.g., `## Overview`), consider skipping the blank line above that heading to keep the header and the first content heading visually grouped.

## Multi-Element Composition Principles

When combining multiple library pieces into a single composition:

1. **Match widths.** Every horizontal element — accent, frame, divider — must be the same width in characters. A 28-character frame above a 34-character divider looks sloppy.
2. **Layer from top to bottom.** Build the accent first, then the frame, then the divider. Adjust widths at each step, working downward.
3. **Less is more.** Three layers is plenty. Adding more rows (a second accent pattern, a subtitle frame, a second divider) creates a header that's taller than the content it introduces.
4. **Reuse the pattern.** Once you've designed one header, copy its structure for all headers in the document. Change only the title text. Consistent header formatting is one of the fastest ways to make a document look polished.

## Alternative Designs

Try these variations to suit different document styles:

**Minimalist** (no accent, single-line frame, single-line divider):
```ascii
┌────────────────┐
│  Section 2     │
└────────────────┘
──────────────────
```

**Celebratory** (heart accent, shadow frame, star divider):
```ascii
♥ ♥ ♥ ♥ ♥ ♥ ♥ ♥

┌────────────────┐
│  🎉 Updates    │
└────────────────┘
  ░░░░░░░░░░░░░░

★ ── ★ ── ★ ── ★
```

**Elegant** (floral accent, rounded frame, dotted divider):
```ascii
✿ ✿ ✿ ✿ ✿ ✿ ✿ ✿

╭────────────────╮
│  Chapter IV    │
╰────────────────╯

. . . . . . . . . .
```

Each design uses three ASCII Library elements combined with different intent. The structure is identical — accent, frame, divider — but the choice of elements produces a completely different feel. Practice by picking a tone from the table above and building a header for each one.
