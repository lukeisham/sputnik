# Example: Cat Art

Creating a recognisable figure from ASCII characters is one of the most satisfying challenges in text-based art. This tutorial walks through building a simple cat face — step by step — using only the characters available in the ASCII Library's Symbol category plus a few standard punctuation marks. The goal is not photorealism but a charming, instantly identifiable silhouette that works at any monospaced font size.

## Step 1: Ears and Head Top

Every cat face starts with the ears. Two forward slashes, an underscore "cap," and two backslashes form the classic pointed-ear silhouette:

```ascii
  /\___/\
```

The underscores between the slashes create the flat top of the head. The carets or spaces inside the ear triangles are left empty at this stage — we'll fill the face in the next step. Count the characters: the slashes and underscores must sit on the same baseline. In monospaced mode, `/`, `\`, and `_` all occupy exactly one cell, so alignment is automatic.

## Step 2: Eyes and Nose

The eyes are the soul of ASCII cat art. Use lowercase `o` characters for wide, curious eyes, and an equals-tilde-equals sequence (`=^=`) for a cute cat nose and mouth:

```ascii
  /\___/\
 (  o o  )
 (  =^=  )
```

The parentheses form the cheeks, creating a rounded face shape. Notice that the cheek lines are indented by one space from the ear line — this gives the head a tapered look, wider at the ears and slightly narrower at the cheeks. The spaces between the `o` eyes and the parentheses keep the face open and readable.

## Step 3: Whiskers and Chin

Add whiskers using angle brackets or equals signs extending outward from the cheeks, and close the chin with a curved underscore line:

```ascii
  /\___/\
 (  o o  )
 (  =^=  )
  (______)
```

The chin line uses four underscores between parentheses, matching the width of the cheek lines above. If the chin is narrower or wider than the cheeks, the face looks lopsided. Count characters carefully: the chin line should have the same total width as the `(  o o  )` line.

## Step 4: Optional Body

For a full-body cat, extend downward from the chin with a simple rectangular torso and a curved tail. A vertical pipe (`|`) for the body and a tilde (`~`) for the tail create a sitting cat posture:

```ascii
  /\___/\
 (  o o  )
 (  =^=  )
  (______)
    |  |
    ~~~~
```

The tail extends to the right of the body with tildes, suggesting a curled, relaxed pose. You can vary the tail character — use a forward slash (`/`) for an alert, upright tail, or a dash (`-`) for a sleeping cat.

## Layering Characters

Successful figure art is about layering simple shapes. The cat above is built from only a dozen unique characters (`/`, `\`, `_`, `(`, `)`, `o`, `=`, `^`, `|`, `~`, and space), yet the arrangement creates an unmistakable cat. The principle applies to any figure: break the subject into geometric primitives (triangles for ears, circles for eyes, curves for the mouth), then translate each primitive into a small cluster of ASCII characters.

## Maintaining Proportions

Proportionality is the difference between a cat and a blob. A few rules keep your figures recognisable:

- **Symmetry is your friend.** Most animal faces are bilaterally symmetric. Build the left half, then mirror it character-by-character for the right half.
- **Eyes at the same height.** If one `o` sits one row higher than the other, the face looks distorted. Use the monospaced column ruler to verify.
- **Width matches height expectations.** A cat face should be roughly as wide as it is tall. If the face is 9 characters wide and 5 rows tall, it reads correctly. If it's 20 characters wide and 2 rows tall, it looks squashed.
- **Step back and squint.** The best test of recognisability is to look at the art from a distance or with unfocused eyes. If the shape reads correctly in your peripheral vision, it will read correctly to readers.

## Using the Symbol Library

The ASCII Library's Symbol collection provides ready-made hearts (`♥`) and stars (`★`) that you can incorporate as embellishments. Place a heart near the cat's face or above its head as a "love" indicator, or use stars as a decorative border around the finished figure. The library's `@{art:ID}` placeholder system means you can swap symbols without manually editing the art.

```ascii
@{art:sym-005}  /\___/\  @{art:sym-005}
 (  o o  )
 (  =^=  )
  (______)
```

## Practice Exercise

Try modifying the base cat to create variations:

1. **Sleepy cat**: Replace `o o` with `- -` for closed eyes.
2. **Surprised cat**: Replace `o o` with `O O` for wide eyes.
3. **Grumpy cat**: Replace `=^=` with `=_=` and angle the eyebrows with `/` and `\`.
4. **Cat with a hat**: Add a row above the ears using `_____` and a vertical extension.

Each variation changes only 2–4 characters but creates a completely different expression. This is the magic of ASCII art: small, precise changes yield big personality shifts.
