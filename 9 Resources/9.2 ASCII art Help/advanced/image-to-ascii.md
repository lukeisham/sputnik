# Image to ASCII Conversion

Sputnik's ASCII Studio can convert any image into ASCII art using a character density ramp. This lets you turn photos, logos, and illustrations into text-based art that you can edit further in the editor.

## How It Works

Every pixel in an image is mapped to a character based on its brightness. Darker pixels become dense characters (`@`, `#`, `W`), lighter pixels become sparse characters (`.`, ` `). The result is a text rendering of your image.

## Converting an Image

1. With a `.asciiArt` document open, click the **Studio** button in the toolbar.
2. Drag an image file onto the Studio panel, or use **File → Import Image**.
3. The Studio immediately renders a preview using the default density ramp.
4. Adjust the **Width** (in characters) to control the output resolution.
5. Click **Insert into Document** to place the ASCII result in your editor.

### Recommended Widths

| Image type | Character width |
|---|---|
| Small icon | 20–40 |
| Avatar / profile pic | 40–60 |
| Logo | 60–80 |
| Full scene / landscape | 80–120 |
| Large poster | 120–200 |

## Tips

- Wider outputs capture more detail but require monospaced display to align properly.
- Portrait images work best at 60–80 characters wide.
- After inserting, you can fine-tune the result by hand in the editor.
