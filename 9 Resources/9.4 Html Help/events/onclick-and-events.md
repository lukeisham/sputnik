# Click & Events

HTML event attributes let you attach JavaScript handlers directly to elements, responding to user interaction.

---

## Common Event Attributes

| Attribute | Triggers When |
|-----------|---------------|
| `onclick` | Element is clicked |
| `ondblclick` | Element is double-clicked |
| `onmouseover` | Mouse enters the element |
| `onmouseout` | Mouse leaves the element |
| `onchange` | Input value changes (after blur for text, immediately for select/checkbox) |
| `oninput` | Input value changes (fires on every keystroke) |
| `onsubmit` | Form is submitted |
| `onfocus` | Element receives focus |
| `onblur` | Element loses focus |
| `onkeydown` | Key is pressed down |
| `onkeyup` | Key is released |
| `onload` | Element (or window) finishes loading |

## Inline vs. `addEventListener`

**Inline handlers** (quick, simple):
```html
<button onclick="alert('Clicked!')">Click me</button>
```

**`addEventListener`** (modern, preferred):
```javascript
document.querySelector('button').addEventListener('click', () => {
  alert('Clicked!');
});
```

### Why `addEventListener` is Better

- **Separation of concerns**: Keeps JavaScript out of HTML.
- **Multiple handlers**: You can attach multiple listeners to the same event.
- **Control**: `removeEventListener` lets you detach handlers.
- **Options**: `{ once: true, passive: true, capture: true }` for fine-grained control.

## Event Propagation

Events bubble up from the target element through its ancestors. Use `event.stopPropagation()` to prevent bubbling and `event.preventDefault()` to cancel the default browser behaviour (e.g., preventing a link from navigating or a form from submitting).

> **Modern practice**: Prefer `addEventListener` in a `<script>` block or external file. Inline event handlers are acceptable for quick prototypes or HTML emails but should be avoided in production code.
