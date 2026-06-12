# Brightness and Contrast

Before converting an image to ASCII, you can adjust its brightness and contrast to improve the tonal distribution of the output. These adjustments are applied to the image *before* the density ramp mapping, giving you control over which parts of the image produce visible characters.

## Brightness

Brightness shifts the entire tonal range up or down:

- **Increase brightness** (+): Lightens the image. Shadows and midtones move toward white, reducing the number of dense characters in the output.
- **Decrease brightness** (−): Darkens the image. More pixels map to dense characters, producing a heavier, darker ASCII result.

**Typical range:** −50 to +50. Default is 0 (no adjustment).

## Contrast

Contrast stretches or compresses the tonal range:

- **Increase contrast** (+): Darkens shadows and lightens highlights simultaneously. Produces a punchier, more posterised ASCII output with fewer midtone characters.
- **Decrease contrast** (−): Compresses the tonal range. More pixels land in the midtone region, producing a flatter, grayer ASCII result with more characters in the mid-density range.

**Typical range:** −50 to +50. Default is 0 (no adjustment).

## Interactive Adjustment

In the ASCII Studio, the brightness and contrast sliders update the preview in real time. Experiment with different combinations:

| Effect | Brightness | Contrast |
|---|---|---|
| Soft, airy look | +10 to +20 | −10 to −20 |
| Bold, high-impact | −10 to −20 | +20 to +30 |
| Even, balanced | 0 | 0 |
| Silhouette effect | −30 to −40 | +40 to +50 |
