# Decorative Patterns

Decorative patterns are the flourish that turns functional ASCII into memorable ASCII. While frames, dividers, and symbols handle structure, decorative patterns handle personality — they set the mood, celebrate the occasion, or simply make a document more enjoyable to read. The ASCII Library's **Decorative** category includes five repeating patterns: star borders, wave lines, diamond rows, floral corners, and heart rows.

## The Decorative Collection

| Pattern | Motif | Mood |
|---------|-------|------|
| Star border | `* . * . *` | Whimsical, celebratory |
| Wave line | `~ ~ ~ ~` | Flowing, calm, organic |
| Diamond row | `◆ ◆ ◆` | Geometric, modern, crisp |
| Floral corner | `✿ ✿ ✿` | Elegant, ornamental, classic |
| Heart row | `♥ ♥ ♥` | Warm, affectionate, personal |

## Borders That Breathe

Unlike frames, which enclose content on all four sides, decorative patterns typically occupy a single row. Stack two identical patterns — one above the content, one below — to create a "bordered" section with far less visual weight than a full frame. This technique is ideal for headers, footers, and section titles.

```ascii
* . * . * . * . * . * . * . *
     ✨ Featured Section ✨
* . * . * . * . * . * . * . *
```

The content between the two decorative rows is the star; the rows themselves are the supporting cast. Keep the interior content short — one or two lines — so the pattern doesn't feel like it's straining to contain too much material.

@{art:deco-001}

The **star border** alternates asterisks and dots in a staggered, woven pattern across three rows. This is the most versatile decorative piece in the library — it works as a header banner, a footer accent, or a full-width section wrapper. The woven star-dot rhythm feels playful without being childish, making it suitable for creative docs, newsletters, and README "about" sections.

@{art:deco-002}

The **wave line** (`~ ~ ~ ~`) flows horizontally with a gentle, undulating rhythm. Unlike rigid straight-line dividers, the wave suggests movement and fluidity. It's perfect for separating sections in creative writing, poetry, or any document where you want the transition to feel organic rather than mechanical. Place a single wave line beneath a title to create a calm, flowing header.

@{art:deco-003}

The **diamond row** (`◆ ◆ ◆`) brings crisp geometry. Each solid diamond sits squarely in its character cell, creating a row that feels structured and modern. Diamond rows work well as subtle separators in technical documents, as they carry more visual interest than a dashed divider but remain professional. Use a single diamond row between sections where a plain divider would feel too dry.

@{art:deco-004}

The **floral corner pattern** (`✿ ✿ ✿`) arranges floral bullet characters in an alternating two-row grid. This pattern has a classic, ornamental quality reminiscent of typographic flourishes. It excels at framing titles and section headers in elegant documents — event programmes, invitations, or creative portfolios. The staggered layout means you should always use it in pairs of rows to preserve the symmetry.

@{art:deco-005}

The **heart row** (`♥ ♥ ♥`) is the most emotionally explicit pattern. A line of hearts immediately warms the tone of any document. Use a single heart row as a document closer (after the last paragraph, before the signature), or sandwich a short dedication or thank-you message between two heart rows. Because hearts carry strong emotional weight, one heart row per document is usually enough — more risks feeling excessive.

## Composing with Patterns

Decorative patterns work best in combination with other ASCII elements. Try these pairings:

- **Heart row + single-line divider** for a warm-but-structured section break.
- **Star border top/bottom + single-line box interior** for a celebratory announcement.
- **Wave line above + diamond row below** for a dual-tone section header.
- **Floral corners around a centered title** for an elegant chapter heading.

```ascii
✿  ✿  ✿  ✿  ✿  ✿  ✿
     Chapter Three
✿  ✿  ✿  ✿  ✿  ✿  ✿
```

## Practical Guidelines

- **One decorative pattern family per document.** Mixing star borders and heart rows and diamond rows on the same page creates visual chaos. Choose a motif and commit to it.
- **Use patterns for special sections, not every section.** If every paragraph has a decorative wrapper, none of them feel special.
- **Test the glyphs.** The `✿` (floral) and `◆` (diamond) characters may not render in all terminal emulators or plain-text viewers. Always preview your document in the target output environment.
- **Keep pattern widths consistent.** If your star border is 40 characters wide, your heart row should also be 40 characters wide. Matching widths create a clean, intentional look.
