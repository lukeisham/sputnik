# Tables

HTML tables display tabular data using a structured grid of rows and cells.

---

## Core Elements

| Element | Purpose |
|---------|---------|
| `<table>` | The table container |
| `<tr>` | Table row |
| `<td>` | Table data cell |
| `<th>` | Table header cell (bold, centred by default) |

## Semantic Grouping

- **`<thead>`**: Wraps header row(s) — typically contains `<th>` elements.
- **`<tbody>`**: Wraps the body rows — the main data area.
- **`<tfoot>`**: Wraps footer row(s) — summary or totals, rendered after `<thead>` but before `<tbody>` in source order.
- **`<caption>`**: A title or description for the table, placed immediately after the opening `<table>` tag. Important for accessibility.

## Spanning Cells

- **`colspan="N"`**: Makes a cell span N columns.
- **`rowspan="N"`**: Makes a cell span N rows.

## Styling Tips

- Use `border-collapse: collapse` to merge adjacent cell borders into a single line.
- Add `padding` to `<td>` and `<th>` for readability.
- Consider zebra striping (`tr:nth-child(even)`) for large tables.
- Use `<th scope="col">` or `<th scope="row">` to associate headers with cells for screen readers.

> **Important**: Tables should only be used for tabular data, never for page layout. For layout, use CSS Grid or Flexbox.
