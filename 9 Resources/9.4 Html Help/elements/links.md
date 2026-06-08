# Links

The `<a>` (anchor) element creates hyperlinks — the foundation of web navigation.

---

## Core Attributes

- **`href`**: The destination URL. Can be absolute (`https://example.com`), relative (`/about`), or a fragment (`#section`).
- **`target`**: Where to open the link. `_self` (default, same tab) or `_blank` (new tab/window).
- **`rel`**: Relationship descriptors. Use `noopener noreferrer` with `target="_blank"` to prevent security vulnerabilities.
- **`title`**: Tooltip text shown on hover (accessibility supplement, not a replacement for visible text).

## Link Types

- **Text links**: `<a href="/page">Click here</a>` — the most common pattern.
- **Image links**: Wrap an `<img>` inside an `<a>` to make images clickable.
- **Email links**: `<a href="mailto:hello@example.com">Email us</a>` — opens the default mail client.
- **Phone links**: `<a href="tel:+1234567890">Call us</a>` — initiates a phone call on mobile devices.
- **Download links**: Add the `download` attribute to trigger a file download instead of navigation.

## Security Note

Always use `rel="noopener noreferrer"` with `target="_blank"`. Without it, the opened page can access `window.opener` and potentially redirect your page to a malicious URL (tabnabbing).
