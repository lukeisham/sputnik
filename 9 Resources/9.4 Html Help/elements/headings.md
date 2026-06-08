# Headings

HTML provides six heading levels, `<h1>` through `<h6>`, which create a hierarchical document outline.

---

## Heading Levels

| Tag | Importance | Typical Use |
|-----|-----------|-------------|
| `<h1>` | Highest | Page title — use **only one** per page |
| `<h2>` | High | Major section headings |
| `<h3>` | Medium | Sub-section headings |
| `<h4>` | Medium–low | Nested sub-headings |
| `<h5>` | Low | Minor headings within deep structures |
| `<h6>` | Lowest | Least prominent headings |

## Best Practices

- **One `<h1>` per page** — it should describe the page's primary topic. Screen readers and search engines rely on this for page context.
- **Don't skip levels** — go from `<h2>` to `<h3>`, not `<h2>` to `<h4>`. This maintains a logical document outline.
- **Use headings for structure, not styling** — if you just want big bold text, use CSS `font-size` and `font-weight` on a `<p>` or `<span>`.
- **Accessibility**: Screen reader users navigate by jumping between headings. A well-structured heading hierarchy makes your content accessible to everyone.
