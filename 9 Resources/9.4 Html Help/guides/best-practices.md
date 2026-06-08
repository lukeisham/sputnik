# HTML Best Practices

Follow these guidelines to write clean, accessible, maintainable HTML.

---

## 1. Write Semantic HTML

Use elements for their intended purpose, not for how they look:

| Instead of... | Use... |
|---------------|--------|
| `<div class="nav">` | `<nav>` |
| `<div class="header">` | `<header>` |
| `<div class="footer">` | `<footer>` |
| `<div class="main">` | `<main>` |
| `<div class="article">` | `<article>` |
| `<div class="sidebar">` | `<aside>` |
| `<span class="btn" onclick="...">` | `<button>` |

Semantic HTML improves accessibility, SEO, and code readability.

## 2. Accessibility Basics (a11y)

- **Language**: Always set `lang="en"` (or appropriate) on the `<html>` element.
- **Alt text**: Every `<img>` must have an `alt` attribute. Use `alt=""` for decorative images.
- **Headings**: Use a logical heading hierarchy (`<h1>` → `<h2>` → `<h3>`). Don't skip levels.
- **Labels**: Every form input should have a `<label>` associated via `for` or wrapping.
- **Keyboard**: Ensure all interactive elements are keyboard-accessible. Use semantic interactive elements (`<button>`, `<a>`, `<input>`) rather than `<div>` with click handlers.
- **ARIA**: Use ARIA attributes only when native HTML semantics aren't sufficient. The first rule of ARIA: don't use ARIA if a native HTML element does the job.

## 3. Validate Your Markup

- Use the [W3C Markup Validation Service](https://validator.w3.org/) to catch syntax errors.
- Ensure all tags are properly closed and nested correctly.
- Use lowercase for tag and attribute names (HTML5 convention, though not required).

## 4. Performance & SEO

- Place `<script>` tags just before `</body>` or use `defer`/`async` to avoid blocking rendering.
- Include a `<meta name="description">` tag for search engine snippets.
- Use responsive `<meta name="viewport">` for mobile-friendly rendering.
- Minimise DOM depth — deeply nested structures slow down rendering and complicate maintenance.

> **Golden rule**: Write HTML for humans first, machines second. Clear, semantic structure benefits everyone — developers, screen readers, search engines, and future maintainers.
