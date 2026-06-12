# Line Art & Edge Detection

Edge detection identifies the boundaries between objects in an image and renders only those boundaries as ASCII characters. This produces a line-art style output that resembles a pencil sketch or engraving.

## How It Works

A Sobel operator scans the image for sharp changes in brightness — edges. Pixels along edges are mapped to characters; flat areas are left as whitespace. The result is a sparse, outline-only ASCII rendering.

## When to Use Edge Detection

| Subject | Result |
|---|---|
| Face / portrait | Recognisable outline, sketch-like |
| Building / architecture | Clean structural lines |
| Product / object | Distinct silhouette and edges |
| Text / signage | Hard to read — skip edge detection |
| Landscape | Works well if distinct foreground/background |
| Photo with busy texture | Too much noise — skip or lower sensitivity |

## Sensitivity

The sensitivity slider (1–100) controls how faint an edge must be to appear:

- **Low (1–30):** Only strong edges appear (bold outlines, minimal detail).
- **Medium (31–60):** A balance between clean lines and recognisable detail.
- **High (61–100):** Faint edges appear, filling in more texture. May look noisy.

## Combining with Standard Conversion

You can use edge detection on its own or combine it with standard density-ramp conversion. The Studio applies them as separate layers, which you can blend for creative effects:

1. Convert the image with the Standard ramp at low width.
2. Add an edge-detection layer on top at medium sensitivity.
3. Adjust the blend to get outlines over a filled background.

## Tips

- Edge detection works best on images with clear subject–background separation.
- For best results, use a high-contrast input image.
- Increase the output width to capture finer edge detail.
