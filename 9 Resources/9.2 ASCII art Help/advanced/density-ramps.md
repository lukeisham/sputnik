# Density Ramps

A density ramp is the set of characters used to represent brightness levels when converting an image to ASCII. The ramp is ordered from darkest (most ink coverage) to lightest (least ink coverage).

## Built-in Ramps

Sputnik provides several density ramps, each suited to a different visual style:

### Standard

```
@%#*+=-:. 
```

The default ramp. Good for general-purpose conversions with smooth tonal range.

### Block

```
█▓▒░ 
```

Uses Unicode block characters for solid, chunky dithering. Best for high-contrast images and logos.

### Minimal

```
@#:. 
```

A short ramp for bold, posterised results. Use when you want a quick, recognisable silhouette.

### Detailed

```
$@B%8&WM#*oahkbdpqwmZO0QLCJUYXzcvunxrjft/\|()1{}[]?-_+~<>i!lI;:,"^`'. 
```

A long ramp that captures subtle tonal variation. Best for photographs and portraits where smooth gradients matter.

## Choosing a Ramp

- **Photographs** → Detailed or Standard ramp
- **Logos and icons** → Block ramp for solid shapes
- **Quick sketches** → Minimal ramp for fast, recognisable output
- **Line art** → Standard ramp with edge detection enabled

## Custom Ramps

You can define your own density ramp in the Studio settings. Characters should be ordered from darkest to lightest. A ramp must contain at least 2 characters; Sputnik recommends 4–10 for good results.
