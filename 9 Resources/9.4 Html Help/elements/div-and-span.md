# Div & Span

The `<div>` and `<span>` elements are the two most fundamental container elements in HTML, used to group and structure content for styling and scripting.

---

## `<div>` — Block-Level Container

- **Display**: Block — starts on a new line and takes the full available width.
- **Use case**: Grouping sections of a page (headers, footers, sidebars, content areas).
- **Common pairings**: Combined with `class` or `id` for CSS styling and JavaScript targeting.
- **Example**: `<div class="card">Content here</div>`

## `<span>` — Inline Container

- **Display**: Inline — flows within text without breaking the line.
- **Use case**: Highlighting or styling a portion of text within a paragraph.
- **Common pairings**: Wrapping words for colour, font-weight changes, or tooltips.
- **Example**: `Price: <span class="highlight">$19.99</span>`

## When to Use Which

- Use `<div>` when you need a structural block (layout containers, cards, panels).
- Use `<span>` when you need to target inline content (a word, a number, a date).
- Both are semantically neutral — they convey no meaning on their own. For meaningful sections, prefer semantic elements like `<section>`, `<article>`, `<nav>`, or `<aside>`.

> **Tip**: Overusing `<div>` leads to "div soup." Use semantic HTML5 elements whenever the content has a clear role.
