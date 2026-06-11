*Sputnik*
 An Angel Creative incubator app. 
 Version 1.0
 
### PURPOSE 

Sputnik is a native macOS development environment that coordinates six concurrent views — a Project File Tree, a Text Editor (Text, Markdown, ASCII art and HTML), a Markdown preview synchronized to the editor, a PDF viewer, a HTML preview also synchronized to the editor, and an integrated Zsh Terminal — within a unified, crash-resistant, memory-efficient minimalist layout, with interactive help guides. (Markdown, ASCII art, English Grammar and HTML) Designed for focused AI agent management, and personal productivity.

### GITHUB

https://github.com/lukeisham/sputnik.git

twitter: @lukeisham

### CREDITS

Keith Foster: software design principles · Nate Jones: AI inspiration

"Man, Sub-creator, the refracted Light
Through whom is splintered from a single White
To many hues, and endlessly combined
In living shapes that move from mind to mind.
...we make still by the law in which we’re made." — J.R.R. Tolkien

---

### TESTING

Sputnik uses **Swift Testing** (not XCTest) for unit tests. Tests live in a `Tests/` subfolder inside each module folder.

To bootstrap test coverage for any module, use the **!CreateTests** skill:

```
!CreateTests: Terminal
!CreateTests: Foundation
```

The skill reads the Module Guide, analyzes source code, generates 20–70 tests per module, and prints a coverage summary.

See [`1 Setup/Guides/Testing.md`](1%20Setup/Guides/Testing.md) for full testing documentation, including Swift Testing syntax, how to run tests (`swift test`), and best practices.

---
