# Arrows and Direction

Arrows are the universal language of flow. In ASCII diagrams, they guide the reader's eye through processes, hierarchies, data flows, and spatial relationships — all without writing a single word of explanation. Sputnik's ASCII Library includes five arrow styles covering horizontal, vertical, bidirectional, and corner-turn directions, giving you a complete toolkit for building clear, readable diagrams.

## The Arrow Family

Each arrow style serves a distinct role in your diagrams:

| Arrow | ID | Best for |
|-------|-----|----------|
| Simple right | `arrow-001` | Primary flow direction, step sequences |
| Double right | `arrow-002` | Emphasised transitions, bold emphasis |
| Up-down | `arrow-003` | Vertical hierarchies, stack flows |
| Left-right | `arrow-004` | Bidirectional relationships, reversible processes |
| Corner (right-down) | `arrow-005` | Branching paths, decision-tree turns |

## Horizontal Flow

The simple right arrow (`──▶`) is the workhorse of left-to-right diagrams. Chain several together with boxes or text labels to create a step-by-step process flow:

```ascii
[Start] ──▶ [Process] ──▶ [Validate] ──▶ [End]
```

For transitions that carry extra weight — a state change, an irreversible step, or a critical path — use the double right arrow (`══▶`). The thicker shaft signals "pay attention to this transition."

```ascii
[Login] ══▶ [Authenticate] ──▶ [Dashboard]
```

@{art:arrow-001}

@{art:arrow-002}

## Vertical and Bidirectional Flow

Not all diagrams run left to right. The up-down arrow (`▲` / `▼`) handles vertical flows: hierarchy trees, stack diagrams, and data pipelines that move top-to-bottom or bottom-to-top.

```ascii
  ▲
  │  Output
  │
  │  Input
  ▼
```

The left-right bidirectional arrow (`◀──▶`) indicates a two-way relationship — data that flows in both directions, a peer-to-peer connection, or a reversible process.

```ascii
Client ◀──────▶ Server
```

@{art:arrow-003}

@{art:arrow-004}

## Corner Turns and Branching

The corner arrow (`┌──▶` then `│` then `▼`) lets a flow change direction mid-diagram. This is essential for decision trees, cause-and-effect chains that can't fit on one horizontal line, and any layout where space is constrained.

```ascii
Question?
   │
   ├── Yes ──▶ [Action A]
   │
   └── No ───▶ [Action B]
```

@{art:arrow-005}

When using the corner arrow, be mindful of the grid: the vertical stem must align perfectly with the horizontal branch. Count columns carefully, and remember that the corner glyph itself consumes one cell in both the horizontal and vertical axes.

## Composing Arrow Diagrams

1. **Start with boxes.** Draw your nodes first (use single-line frames), then connect them with arrows.
2. **Keep paths short.** If an arrow spans more than 40 characters, consider breaking the diagram into two rows.
3. **Label every arrow** unless the direction is obvious. A short word like "yes," "no," "success," or "timeout" above or beside the arrow adds enormous clarity.
4. **Stay in monospaced mode.** Even a single proportional space will misalign an arrow's shaft.
5. **Test the corner arrow before committing.** The `┌` and `│` and `▼` glyphs are drawn from different Unicode blocks; verify they render correctly in your target output.
