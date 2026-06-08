# Images

The `<img>` element embeds images into an HTML document. It is a void element (self-closing).

---

## Required Attributes

- **`src`**: The image source URL. Can be relative, absolute, or a data URI.
- **`alt`**: Alternative text describing the image. **Always include this** — it is critical for accessibility and is displayed when the image fails to load.

## Important Optional Attributes

- **`width` / `height`**: Intrinsic dimensions in pixels. Specifying these prevents layout shift (Cumulative Layout Shift / CLS) as the page loads.
- **`loading`**: Set to `"lazy"` to defer loading off-screen images until the user scrolls near them. Improves initial page load performance.
- **`srcset`** and **`sizes`**: For responsive images, provide multiple resolutions and let the browser choose the best one based on viewport width and device pixel ratio.
- **`title`**: Tooltip on hover (supplementary — do not rely on it for critical information).

## Accessibility Guidelines

- **Decorative images**: Use `alt=""` (empty string) so screen readers skip them.
- **Informative images**: The `alt` text should convey the same information the image provides.
- **Complex images** (charts, diagrams): Provide a longer description nearby or link to a separate page with full details.

## Formats

Use modern formats for best performance: **WebP** (broad support, smaller files), **AVIF** (even smaller, newer), with **JPEG** and **PNG** as fallbacks.
