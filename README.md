*Sputnik*
An Angel Creative incubator app. 

### PURPOSE 

Sputnik is a native macOS development environment that coordinates six concurrent views — a Project File Tree, a Text Editor (Text, Markdown, ASCII art and HTML), a Markdown preview synchronized to the editor, a PDF viewer, a HTML preview also synchronized to the editor, and an integrated Zsh Terminal — within a unified, crash-resistant, memory-efficient minimalist layout, with interactive help guides. (Markdown, ASCII art, Grammar and HTML)

### GITHUB

https://github.com/lukeisham/sputnik.git

### CREDITS

Keith Foster: software design principles & Nate Jones: AI inspiration

"Man, Sub-creator, the refracted Light
Through whom is splintered from a single White
To many hues, and endlessly combined
In living shapes that move from mind to mind.
...we make still by the law in which we’re made." — J.R.R. Tolkien

---

### SETUP & BUILD

Sputnik uses a **hybrid layout**: reusable logic lives in local Swift packages, and a thin macOS app target wires them into a window.

### Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 with the Swift 6.2+ toolchain (`swift --version` ≥ 6.2)

### Repository layout

```
App_Sputnik/
├── Packages/
│   ├── CoreSputnik/          ← App-agnostic core (versioning, shared types, errors)
│   ├── NetworkingSputnik/    ← URLSession-based HTTP client
│   └── UIComponentsSputnik/  ← Reusable SwiftUI views (e.g. TitleBar)
└── App-Sputnik/
    ├── App-SputnikApp.swift  ← @main entry point + placeholder ContentView
    ├── Info.plist            ← Bundle metadata (uses build-setting variables)
    ├── App-Sputnik.entitlements ← App Sandbox, network client, user-selected files
    └── Configs/
        ├── Debug.xcconfig    ← Debug build settings
        └── Release.xcconfig  ← Release build settings
```

Each package is a standalone, independently testable Swift package — this keeps Sputnik's modular design rule intact (logic compiles and tests without the app shell).

### Build & test the packages (no Xcode UI needed)

```sh
# From the repo root, build/test any package:
cd Packages/CoreSputnik        && swift test
cd ../NetworkingSputnik        && swift test
cd ../UIComponentsSputnik      && swift build   # SwiftUI views; build verifies compilation
```

All three target `.macOS(.v26)` and use the Swift Testing framework (`import Testing`).

### Build & run the app

The app shell links the three packages and applies the entitlements/configs, so it is built through Xcode. A `.xcodeproj` is intentionally **not** committed yet — create the app target once, locally:

1. Open Xcode → **File ▸ New ▸ Project… ▸ macOS ▸ App**. Name it `App-Sputnik`, interface **SwiftUI**, language **Swift**. Save it at the repo root.
2. Delete the auto-generated `ContentView.swift`/`App.swift` and instead **add the existing** `App-Sputnik/App-SputnikApp.swift` to the target.
3. In **File ▸ Add Package Dependencies… ▸ Add Local…**, add each folder under `Packages/`, and link the `CoreSputnik`, `NetworkingSputnik`, and `UIComponentsSputnik` products to the app target.
4. In the target's **Info** and **Build Settings**:
   - Set the **Info.plist File** to `App-Sputnik/Info.plist`.
   - Set **Code Signing Entitlements** to `App-Sputnik/App-Sputnik.entitlements`.
   - Under **Project ▸ Info ▸ Configurations**, set the Debug/Release configs to the `.xcconfig` files in `App-Sputnik/Configs/`.
5. Select your signing team (or use **Sign to Run Locally**) and press **⌘R**.

You should see a window titled *Sputnik* showing the Core version string and the shared `TitleBar` component — confirming all three packages are linked.

> The bundle identifier defaults to `com.example.App-Sputnik` (set in the `.xcconfig` files). Change it to your own reverse-DNS identifier before distribution.

---
