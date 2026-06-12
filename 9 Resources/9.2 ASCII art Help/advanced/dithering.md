# Dithering

Dithering is a technique that simulates smooth gradients by placing characters in a patterned arrangement. Instead of mapping each pixel to a single character by brightness, dithering uses a matrix to distribute error across neighbouring pixels, producing the illusion of more colours or shades than the character set actually provides.

## When to Use Dithering

| Situation | Recommendation |
|---|---|
| Photo with smooth gradients | ✅ Enable dithering |
| Logo with flat colours | ❌ Skip; Block ramp works better |
| Low-width output (under 40 chars) | ✅ Dithering improves perceived detail |
| Line art or text-heavy image | ❌ Dithering adds noise |
| Portrait | ✅ Dithering preserves skin tones |

## Dithering Methods

Sputnik offers two dithering algorithms:

### Floyd–Steinberg

Distributes quantization error to neighbouring pixels in a serpentine pattern. Produces the most detailed result but can introduce characteristic noise patterns. Best for high-resolution outputs where the noise is less visible.

### Atkinson

A modified algorithm that distributes less error to neighbours, resulting in cleaner output with fewer noise artefacts. Atkinson preserves more of the original image's character at the cost of slightly less smooth gradients.

## Dithering Strength

The strength slider (0–100%) controls how aggressively dithering is applied:

- **0%** : No dithering — pure per-pixel mapping (fastest)
- **30–50%** : Subtle dithering — smoother gradients without heavy noise
- **70–100%** : Full dithering — maximum smoothness, may introduce visible noise patterns
