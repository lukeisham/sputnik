# Style Attribute

The `style` attribute applies inline CSS directly to a single HTML element.

---

## Syntax

```html
<element style="property: value; property: value;">
```

- Properties and values are separated by colons.
- Multiple declarations are separated by semicolons.
- Example: `<p style="color: red; font-size: 16px;">Styled text</p>`

## Common Use Cases

- **Dynamic values**: Styles computed at runtime (e.g., a progress bar width from JavaScript).
- **Quick prototyping**: Testing a visual change before moving it to a stylesheet.
- **Email HTML**: Many email clients strip `<style>` blocks and external stylesheets, so inline styles are the only reliable option.
- **One-off exceptions**: Overriding a global style for a single element without creating a new class.

## When to Avoid

- **Production websites**: Inline styles are hard to maintain, can't be cached, and bloat HTML size.
- **Repetitive styles**: If the same styles appear on multiple elements, extract them into a CSS class.
- **Responsive design**: Inline styles can't use media queries. Use a `<style>` block or external stylesheet.
- **Pseudo-classes**: You can't target `:hover`, `:focus`, or `::before` with inline styles.

## Specificity

Inline styles have very high specificity — they override any external or embedded CSS (except `!important`). This makes debugging difficult when inline styles are scattered throughout a codebase.

> **Rule of thumb**: Use `<style>` blocks or external `.css` files for styling. Reserve the `style` attribute for truly dynamic or email-specific cases.
