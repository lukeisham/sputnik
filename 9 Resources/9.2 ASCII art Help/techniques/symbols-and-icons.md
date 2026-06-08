# Symbols and Icons

Symbols are the punctuation marks of visual communication. A single well-placed checkmark, warning triangle, or star can convey an entire sentiment — done, danger, favourite — without a full sentence. In ASCII art, symbols sit inline with text or stand alone as compact accent marks. The ASCII Library's **Symbols** category provides five essential icons that cover the most common signalling needs in documentation, notes, and creative writing.

## The Symbol Set

| Symbol | Art | Meaning | Placement |
|--------|-----|---------|-----------|
| Checkmark | `✓` | Done, confirmed, correct | Inline, list prefix |
| Warning | `⚠` | Caution, watch out | Standalone, section header |
| Info | `ⓘ` | Note, tip, FYI | Inline, margin |
| Star | `★` | Important, favourite, highlight | Inline, list prefix |
| Heart | `♥` | Love, like, appreciate | Inline, footer accent |

## Inline vs Standalone

Symbols work in two modes: **inline**, where they sit beside text as a prefix or suffix, and **standalone**, where they occupy their own line as a visual marker.

```ascii
✓ Task completed          ← inline prefix
⚠                        ← standalone
Configuration file missing — check settings.
```

Inline symbols integrate seamlessly with Markdown lists. Replace the standard `-` bullet with a symbol to create a status list:

```ascii
✓ Install dependencies
✓ Configure environment
⚠ Run migration script
✗ Deploy to production  (pending review)
```

Standalone symbols draw the eye before the reader reaches the text. A warning triangle on its own line, followed by an indented explanation, creates a stronger alert than an inline `⚠` ever could.

@{art:sym-001}

The **checkmark** (`✓`) is your universal "done" signal. Use it in task lists, changelogs, and acceptance criteria. It's unambiguous across cultures and instantly recognisable at small font sizes. Pair it with a strikethrough for maximum clarity: `✓ ~~Old approach~~`.

@{art:sym-002}

The **warning triangle** (`⚠`) demands a pause. It's constructed from three slashes and underscores to form a triangular alert icon that reads clearly even in plain-text environments. Place it before any instruction that could cause data loss, a broken build, or an irreversible action. The triangle says "read this before proceeding."

@{art:sym-003}

The **info badge** (`ⓘ`) is the gentler cousin of the warning. It signals "here's something useful to know" without the urgency of a warning. Use it in tutorials for tangential tips, in READMEs for version notes, and in code comments for context that doesn't fit on one line.

@{art:sym-004}

The **star** (`★`) marks items as important, favourite, or featured. In a list of 20 items, a single star next to item #7 tells the reader "this one matters most." Stars also work well as rating indicators: `★★★★☆` communicates a 4-out-of-5 score in five characters.

@{art:sym-005}

The **heart** (`♥`) adds warmth. Use it sparingly — one heart in a document feels personal; ten hearts feel like a Valentine's card. Hearts work beautifully as footer accents, section closers, or subtle endorsements. Avoid hearts in formal documentation where they may undermine professional tone.

## Combining Symbols

Symbols become more powerful when combined. A checkmark beside a star says "this important task is done." An info badge beside a warning says "read this caution, then see the note for details." Experiment with two-symbol pairs before trying three — more than two inline symbols on one line can look noisy.

```ascii
★ ✓  Critical path — completed and verified
⚠ ⓘ  Configuration change required — see notes below
```

## Practical Tips

- **Stick to one or two symbol types per document.** Using all five in a single page dilutes each symbol's meaning.
- **Place symbols at the start of a line** for maximum visibility. Readers scan the left margin first.
- **Don't use symbols as substitutes for clear writing.** A warning triangle next to a vague sentence is no better than a vague sentence alone.
- **Test rendering in your target output.** Some terminals and plain-text viewers may not render the `ⓘ` or `⚠` glyphs correctly. The library's fallback ensures the art degrades gracefully, but always verify.
