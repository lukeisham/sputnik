# Drawing Shapes

Drawing geometric shapes with ASCII characters is the foundation of structured ASCII art. Boxes, rectangles, and other outlined forms are built from **box-drawing characters** — a set of Unicode glyphs designed specifically for monospaced grid work. The core set includes `┌` (top-left), `┐` (top-right), `│` (vertical), `─` (horizontal), `└` (bottom-left), and `┘` (bottom-right). When combined, they form seamless single-line rectangles that look like a continuous border.

## Box-Drawing Characters

Here is a quick reference for the single-line box set:

| Character | Name | Position |
|-----------|------|----------|
| `┌` | Light down-and-right | Top-left corner |
| `┐` | Light down-and-left | Top-right corner |
| `│` | Light vertical | Left & right edges |
| `─` | Light horizontal | Top & bottom edges |
| `└` | Light up-and-right | Bottom-left corner |
| `┘` | Light up-and-left | Bottom-right corner |

To build a box, think of it as three rows: a top edge (corners connected by horizontals), one or more middle rows (verticals with whitespace between them), and a bottom edge. The width is the number of horizontal characters between the verticals; the height is the number of middle rows plus two.

```ascii
┌──────────────────┐
│                  │
│    Your text     │
│                  │
└──────────────────┘
```

## Maintaining Grid Alignment

All box-drawing characters consume exactly one monospaced cell, so they naturally align on the grid. The most common pitfall is mixing a proportional-width character (like a standard space or an emoji) into a line where every column matters. Always stay in **monospaced mode** while constructing shapes. Use the column ruler to verify that the left and right edges of every row land on the same column number. A single misaligned pipe will throw off the entire rectangle.

## Beyond Rectangles

Once you're comfortable with single-line boxes, try extending the shape language: use the same corner characters to build L-shapes, T-junctions, and cross intersections by borrowing glyphs like `├`, `┤`, `┬`, `┴`, and `┼`. These allow you to create flowcharts, tree diagrams, and nested panels without breaking the monospaced grid.

```ascii
├── Left branch
│
├── Center branch
│   ├── Sub-item
│   └── Sub-item
│
└── Right branch
```

## Reference Frames

The ASCII Library provides several pre-built frame styles you can drop in and resize. Below are three of the most commonly used frames — study their corner and edge characters to understand how each style communicates a different tone.

@{art:frame-001}

The single-line box (above) is your everyday workhorse. It's clean, unobtrusive, and works for notes, code snippets, and general framing.

@{art:frame-002}

The double-line box adds visual weight. Use it for section headers, important callouts, or any content you want readers to notice first.

@{art:frame-003}

The rounded box feels softer and friendlier. It pairs well with informal docs, chat logs, or creative writing where sharp corners might feel too rigid.

## Pro Tips

- **Count your horizontals.** If the top edge has 20 `─` characters, every middle row needs exactly 20 spaces between the verticals.
- **Copy-paste the top edge** to create the bottom edge — swap `┌` for `└` and `┐` for `┘`.
- **Use the library's frames as templates.** Insert one, then edit the interior to fit your content rather than drawing from scratch each time.
