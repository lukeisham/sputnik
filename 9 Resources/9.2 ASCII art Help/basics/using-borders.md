# Using Borders

Borders are the visual fences of your document — they separate, emphasise, and organise content so readers can navigate your layout at a glance. In ASCII art, a border is any continuous line or pattern that surrounds a block of text or art. Sputnik's editor and ASCII Library give you several border styles, each suited to a different purpose. Choosing the right border is as much about tone as it is about structure.

## Single-Line vs Double-Line vs Rounded

The three fundamental border styles — single-line (`┌─┐`), double-line (`╔═╗`), and rounded (`╭─╮`) — form a visual hierarchy. Think of them like heading levels in Markdown: single-line is your `h3`, double-line is your `h2`, and rounded is a stylistic variant you can mix in for variety.

```ascii
┌──────────────────────┐   ← single-line: neutral, everyday use
│  Meeting notes       │
└──────────────────────┘

╔══════════════════════╗   ← double-line: prominent, authoritative
║  ACTION REQUIRED     ║
╚══════════════════════╝

╭──────────────────────╮   ← rounded: soft, approachable
│  Friendly reminder   │
╰──────────────────────╯
```

Single-line borders disappear into the background — they frame content without shouting. Double-line borders demand attention and are ideal for warnings, deadlines, and critical information. Rounded borders feel conversational; use them for tips, asides, or any content where a hard-edged box would feel too formal.

## Visual Hierarchy

When a document contains multiple bordered blocks, readers instinctively rank them by visual weight. A thick or double-lined border reads as "more important" than a single-lined one. Use this to your advantage:

- **Critical warnings** → double-line or thick border
- **Key takeaways** → single-line with a bold interior
- **Tangential notes** → rounded border
- **Code examples** → single-line, no fill

Stack borders sparingly. Two bordered blocks with one blank line between them is fine; three or more in a row creates visual clutter. When in doubt, replace one border with a simple divider to give the remaining border more impact.

## Decorative Borders

Beyond the standard box-drawing styles, decorative patterns can serve as borders for headers, footers, or full-page frames. Star borders, wave lines, and floral corners (available in the Decorative category of the ASCII Library) add personality without sacrificing structure.

@{art:frame-004}

The thick-line box (above) is the boldest option in the library. It uses heavy block-drawing characters (`┏━┓`) that occupy the full character cell, creating a dense, high-contrast border. Reserve this for the single most important block on the page.

@{art:frame-005}

The shadow box adds a drop-shadow effect (`░░░`) beneath a standard single-line frame. The shadow creates a subtle illusion of depth — the content appears to float above the page. Shadow boxes work beautifully for pull quotes, featured snippets, and hero sections.

@{art:deco-001}

The star border pattern (above) alternates stars and dots in a repeating row. When stacked as a top and bottom pair with content between them, it creates a festive or celebratory container. Use it for newsletter headers, event announcements, or any content that calls for a touch of whimsy.

## Practical Guidelines

1. **Pick one border style per document** and use variations of it. Mixing single-line, double-line, and rounded borders arbitrarily confuses the reader's sense of hierarchy.
2. **Match border width to content width.** A border that's 20 characters wider than the text inside it looks sloppy. Trim or pad the interior text so there's one space of padding on each side.
3. **Leave breathing room.** Always place at least one blank line above and below a bordered block.
4. **Test at different font sizes.** The library previews in your editor's current font, but if you expect the document to be read at a smaller size, double-check that the border characters remain distinguishable.
