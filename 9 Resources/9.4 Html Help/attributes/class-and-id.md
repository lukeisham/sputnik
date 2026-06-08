# Class & ID

`class` and `id` are the two most important HTML attributes for targeting elements with CSS and JavaScript.

---

## `class` — Reusable Group Selector

- Multiple elements can share the same class.
- An element can have multiple classes separated by spaces: `class="card highlighted rounded"`.
- Use classes for **reusable styling patterns** — all cards, all buttons, all alerts.
- CSS selector: `.classname` (e.g., `.card { ... }`).
- JavaScript: `document.querySelectorAll('.card')`.

## `id` — Unique Element Identifier

- Must be **unique** within the page — no two elements should share the same `id`.
- Use for: anchor links (`#section`), JavaScript targeting (`document.getElementById`), form label associations (`<label for="email">`).
- CSS selector: `#idname` (e.g., `#main-header { ... }`).
- An element can have only **one** `id`.

## CSS Specificity

IDs have **higher specificity** than classes:

- `#my-id` beats `.my-class` in the cascade.
- Inline `style=""` beats both.
- `!important` beats everything (use sparingly).

This means if you write:
```css
#header { color: red; }
.header { color: blue; }
```
`<div id="header" class="header">` will be red, because `#header` is more specific.

## Best Practices

- **Prefer classes over IDs for styling** — they're reusable and keep specificity low.
- **Use IDs for unique page anchors and JavaScript hooks** — not for CSS unless necessary.
- **Naming conventions**: Use descriptive, semantic names like `.product-card` or `#contact-form`, not `.box1` or `#div42`.
