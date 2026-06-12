# Opening Existing Art

You can open existing ASCII art in the ASCII Studio for editing, re-conversion, or export. Sputnik supports several ways to bring art into the Studio.

## From the Editor

If you have ASCII art in a `.asciiArt` document:

1. Select the art you want to edit in the editor.
2. Right-click and choose **Open in Studio**.
3. The Studio opens with your selection loaded as a character grid.

Alternatively, use the **Studio → Import from Editor** menu command to load the full document.

## From the ASCII Library

To open a library piece in the Studio:

1. Open the ASCII Library browser (⌘⇧L).
2. Find the piece you want to edit.
3. Click the **Open in Studio** button on the detail panel.
4. The piece is loaded into the Studio with its current character grid preserved.

## From an Image File

Drag an image file (`PNG`, `JPEG`, `GIF`, `BMP`, `TIFF`, `HEIC`) onto the Studio panel. The image is loaded as a source for conversion — it appears in the preview area, and you can adjust conversion settings before generating the ASCII output.

## From Plain Text

Copy ASCII art from any source (web, email, another app) and paste it directly into the Studio canvas with ⌘V. The Studio detects the monospaced layout and loads it as an editable character grid.

## Supported File Formats for Import

| Format | Import as |
|---|---|
| `.asciiArt` | Character grid (editable) |
| `.txt` | Character grid (editable) |
| `PNG`, `JPEG`, `GIF`, `BMP` | Source image (requires conversion) |
| `TIFF`, `HEIC` | Source image (requires conversion) |
