# Saving & Exporting

Once you've created or edited ASCII art in the Studio, you can save it to a document or export it in several formats.

## Saving to a Document

- **Save** (⌘S): Saves the current Studio content to the active `.asciiArt` document.
- **Save As** (⇧⌘S): Saves to a new `.asciiArt` file.

Studio content is always stored as plain text with monospaced layout preserved.

## Inserting into the Editor

Click **Insert into Document** in the Studio toolbar. The ASCII art is placed at the cursor position in the editor. You can then continue editing it as plain text.

## Exporting

The Studio supports these export formats:

### Plain Text (`.txt`)

Exports the character grid as-is. Universal compatibility — any text editor can open it. The recommended format for sharing.

### HTML (`.html`)

Wraps the ASCII art in a `<pre>` block with monospaced styling. Useful for publishing on the web.

### PNG Image (`.png`)

Renders the ASCII art as a raster image using a monospaced font. Each character is rendered at the specified font size. Best for sharing on social media or in documents that don't support monospaced text.

### SVG (`.svg`)

Renders the ASCII art as an SVG with `<text>` elements positioned on a grid. Scalable without quality loss. Best for presentations and vector design tools.

## Export Settings

When exporting to PNG or SVG, you can configure:

- **Font**: The monospaced font to use for rendering (default: SF Mono).
- **Font size**: Character size in points (default: 12).
- **Foreground colour**: Character colour (default: current editor text colour).
- **Background colour**: Canvas colour (default: current editor background colour).
