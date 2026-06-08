# Dividers and Separators

Dividers are the quiet organisers of a document. A thin horizontal rule between two paragraphs tells the reader "a new section starts here" without using a heading. A heavier divider between major parts signals a more significant break. Sputnik's ASCII Library offers five divider styles — single, double, dashed, dotted, and star — each carrying a different level of visual weight for different organisational needs.

## The Divider Family

| Divider | Character(s) | Visual Weight | Best For |
|---------|-------------|---------------|----------|
| Single line | `─` | Light | Sub-section breaks, topic shifts |
| Double line | `═` | Medium | Major section breaks, chapter ends |
| Dashed | `- -` | Very light | Minor asides, thought breaks |
| Dotted | `. . .` | Subtle | Whisper breaks, poetic pauses |
| Star | `★ ── ★` | Decorative | Festive breaks, creative docs |

@{art:div-001}

The **single line divider** is your everyday separator. At 30 characters wide, it spans roughly half the width of a typical document, creating a clean horizontal rule that readers barely notice — which is exactly the point. Use it between sub-sections, before and after code blocks, or to separate a list from its surrounding text.

@{art:div-002}

The **double line divider** is bolder and more intentional. The twin strokes make the break feel like a genuine section boundary. Place one before each major heading to establish a rhythm: divider, heading, content, divider, heading, content. This pattern works especially well in README files, meeting notes, and long-form documentation.

@{art:div-003}

The **dashed divider** uses alternating hyphens and spaces (`- - -`) to create a light, airy break. It's subtle enough to place between related paragraphs where a solid line would feel too heavy. Think of it as a "soft return" for sections — a pause, not a stop.

@{art:div-004}

The **dotted divider** is the most understated option. The dots (`...`) create a whisper of separation, ideal for creative writing, poetry, or any document where you want the break to be felt rather than seen. It also works well as a "thinking pause" between steps in a tutorial.

@{art:div-005}

The **star divider** combines stars with short horizontal dashes (`★ ── ★ ── ★`), blending structure with decoration. It brings personality to a break without being as loud as a decorative pattern. Use it in newsletters, event programmes, or any document where a plain divider would feel too sterile.

## Matching Divider Tone to Document

The divider you choose should match the document's overall tone:

- **Technical docs, READMEs, specs** → single and double line dividers. Clean, professional, unambiguous.
- **Blog posts, newsletters, creative writing** → dashed, dotted, or star dividers. Friendly, expressive, human.
- **Meeting notes, internal memos** → single line dividers. Efficient, scannable.

A single document rarely needs more than two divider styles. Pick a primary style for most breaks and a secondary style for the biggest section transitions. Using all five styles in one document confuses the reader about the document's structure.

## Divider Dos and Don'ts

- **Do** place one blank line above and below every divider so it breathes.
- **Do** keep divider width consistent across your document. If you use 30-character single-line dividers, use 30-character double-line ones too.
- **Do** use a divider *instead* of a heading when the content shift is minor.
- **Don't** stack two dividers consecutively. One is enough.
- **Don't** use a divider immediately after a heading — the heading itself already signals a break. The combination looks cluttered.
- **Don't** make dividers wider than your text column. A divider that extends past the right margin draws attention for the wrong reason.
