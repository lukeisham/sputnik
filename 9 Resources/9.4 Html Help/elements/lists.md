# Lists

HTML supports three types of lists: unordered, ordered, and definition lists.

---

## Unordered Lists (`<ul>`)

- Renders items with bullet points.
- Each item wrapped in `<li>`.
- Default bullet style is `disc`; can be changed with CSS `list-style-type` (`circle`, `square`, `none`).

## Ordered Lists (`<ol>`)

- Renders items with sequential numbers or letters.
- Each item wrapped in `<li>`.
- Use the `start` attribute to begin at a number other than 1.
- Use `type` to change numbering: `"1"` (default), `"A"` (uppercase letters), `"a"` (lowercase), `"I"` (uppercase roman), `"i"` (lowercase roman).
- The `reversed` attribute counts down instead of up.

## Definition Lists (`<dl>`)

- For term–description pairs (glossaries, metadata).
- `<dt>` = definition term.
- `<dd>` = definition description.
- One `<dt>` can have multiple `<dd>` elements.

## Nesting

Lists can be nested to any depth:
```html
<ul>
  <li>Item 1</li>
  <li>Item 2
    <ul>
      <li>Nested A</li>
      <li>Nested B</li>
    </ul>
  </li>
</ul>
```

## Styling Tips

- Remove default padding/margin with `list-style: none; padding: 0; margin: 0;` for custom designs.
- Use `display: inline` or `display: inline-block` on `<li>` for horizontal navigation menus.
