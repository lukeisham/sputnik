# Data Attributes

`data-*` attributes let you store custom data directly on HTML elements without using non-standard attributes or hidden inputs.

---

## Syntax

```html
<div data-user-id="42" data-role="admin" data-last-login="2026-01-15">
```

- Must start with `data-`.
- The part after `data-` becomes the property name (hyphens are converted to camelCase).
- Values are always strings — convert to numbers/booleans as needed in JavaScript.

## Accessing in JavaScript

```javascript
const el = document.querySelector('div');
el.dataset.userId;     // "42"
el.dataset.role;       // "admin"
el.dataset.lastLogin;  // "2026-01-15"
```

- Use `element.dataset` to read and write.
- Setting `el.dataset.newValue = "hello"` creates `data-new-value="hello"` in the DOM.

## Common Use Cases

- **Storing IDs**: Link a DOM element to a database record (`data-id="7283"`).
- **Configuration**: Toggle behaviour flags (`data-expanded="true"`, `data-sort="asc"`).
- **CSS hooks**: Style elements conditionally with attribute selectors:
  ```css
  [data-status="error"] { border-color: red; }
  [data-status="success"] { border-color: green; }
  ```
- **Passing data to JavaScript frameworks**: Many frameworks (Alpine.js, Stimulus, HTMX) use `data-*` attributes for configuration.
- **Test selectors**: `data-testid="submit-button"` for end-to-end tests (decoupled from styling classes).

## Limitations

- Not suitable for large data — use `<script type="application/json">` blocks for structured data.
- Values are always strings — parse numbers and booleans explicitly.
- Not encrypted or hidden — visible in page source. Don't store secrets.
