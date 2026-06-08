# Frames and Boxes

Frames are the containers that give your content a stage. A well-chosen frame signals to the reader what kind of content they're about to encounter — a casual note, an urgent warning, a code snippet, or a decorative pull quote — before they've read a single word. The ASCII Library provides five frame styles, each with distinct corner and edge characters that create a different visual personality.

## The Five Frame Styles

| Frame | Corners & Edges | Visual Weight |
|-------|-----------------|---------------|
| Single-line | `┌─┐ │ └─┘` | Light |
| Double-line | `╔═╗ ║ ╚═╝` | Medium-heavy |
| Rounded | `╭─╮ │ ╰─╯` | Light, soft |
| Thick-line | `┏━┓ ┃ ┗━┛` | Heavy |
| Shadow | Single-line + `░░░` shadow | Medium, dimensional |

Each frame can be resized by adding or removing horizontal (`─`, `═`, `━`) and vertical (`│`, `║`, `┃`) characters. The corners remain fixed; only the edge lengths change.

@{art:frame-001}

The **single-line box** is your default. It adds structure without drawing attention to itself. Use it for code examples, meeting notes, document metadata, and any content where the frame should be invisible to the reader.

@{art:frame-002}

The **double-line box** is a step up in visual prominence. The twin strokes make the border feel deliberate and authoritative. It's the right choice for section summaries, key findings, or the single most important block on a page.

@{art:frame-003}

The **rounded box** replaces sharp corners with gentle arcs. This softens the frame's presence and makes the content feel more conversational. Perfect for tips, "pro-tip" callouts, and friendly reminders. Avoid rounded boxes for warnings — the soft corners work against the sense of urgency.

@{art:frame-004}

The **thick-line box** uses solid block-drawing characters (`┏┓┗┛┃━`) that fill the entire character cell, producing the heaviest border in the library. It's unmissable. Reserve it for critical warnings, "do not skip" notices, and emergency-level callouts. Using thick-line boxes for everyday content dilutes their impact.

@{art:frame-005}

The **shadow box** combines a single-line frame with a row of light-shade characters (`░░░`) offset beneath the bottom edge, creating a drop-shadow effect. The shadow gives the box a subtle 3D lift — it pops off the page. Shadow boxes excel at pull quotes, featured excerpts, and testimonials where you want the content to feel special without the gravity of a double or thick border.

## Choosing the Right Frame for the Tone

| Tone / Intent | Recommended Frame |
|---------------|-------------------|
| Neutral note, code block | Single-line |
| Important finding, summary | Double-line |
| Tip, suggestion, aside | Rounded |
| Warning, critical alert | Thick-line |
| Pull quote, featured content | Shadow |

A document should rarely mix more than two frame styles. Consistency helps the reader internalise the visual language. If you use double-line boxes for section summaries, use them for *all* section summaries.

## Resizing Frames

To resize any frame, adjust the number of horizontal edge characters between the corners. For example, to widen a single-line box from 20 columns to 30, add 10 more `─` characters to the top and bottom edges, and 10 more spaces to the interior of each middle row. The corners (`┌`, `┐`, `└`, `┘`) stay put. The same rule applies to every frame style: stretch the edges, leave the corners.

```ascii
┌──────────────┐     ┌──────────────────────────┐
│ Narrow box   │  →  │ Wide box with more room   │
└──────────────┘     └──────────────────────────┘
```

Always verify alignment after resizing. The quickest check: count the characters on the top edge, then count the characters between the vertical bars on any middle row. They must match exactly.
