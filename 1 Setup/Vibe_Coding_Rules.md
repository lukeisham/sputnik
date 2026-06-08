# Vibe Coding Rules

Rules are numbered so `!TrackIssues` can cite them precisely (e.g. `Swift Rule 2`).

---

## Sputnik Rules

**SR-1 — Modular design**
Each module owns its own state and types. No module reaches into another module's internals. Cross-module communication goes through the shared Foundation layer (module 2) only.

UI/UX primitives (colours, fonts, spacing, dialogue boxes, toggles, icons, light/dark mode, layout state persistence) are defined once in Foundation (module 2.3) and consumed by all other modules. A module only contains its own UI code when the component is specific to that module's function (e.g. the PDF thumbnail strip, the terminal input bar). When in doubt, the rule is: if two modules could share it, it belongs in Foundation.

Foundation exposes **protocols and configuration tokens**, not concrete glue logic. When module A needs to trigger behaviour in module B, it calls a protocol registered in Foundation — it does not call module B's implementation directly, and Foundation does not contain the implementation either. Keep Foundation as an interface layer, not an orchestration layer.

**SR-2 — Error and crash proof**
Every failure path must be handled explicitly. No force-unwraps (`!`) in non-test code. Use `guard let` / `if let` / `Result` / `throws`. Assume file I/O, shell processes, and PDFKit calls can fail at any time.

**SR-3 — Low RAM usage**
Never load a file into memory when it can be streamed. Lazy-load views, pages, and directory contents. Release resources as soon as they go out of scope. Refuse to open binary or oversized files (see module 3 spec).

**SR-4 — Fast and efficient**
The main thread renders UI only. Any work that touches the file system, shell, PDF parsing, or syntax highlighting must run on a background Task or GCD queue. Use appropriate QoS levels — don't promote everything to `.userInteractive`.

**SR-5 — Use existing macOS frameworks**
Reach for Apple's built-in APIs before adding any dependency. No third-party Swift packages without explicit approval. If a native framework covers the need, use it.

**SR-6 — One responsibility per file**
Each file should contain one function, type, or clearly scoped responsibility. Group into a single file only when functions are closely related (operate on the same type or data) or sequentially related (one always calls the next as part of a single pipeline). If you are unsure whether two things belong together, they belong in separate files.

| Put in one file | Split into separate files |
|---|---|
| `open(_ url:)` + `close(_ url:)` — same resource lifecycle | `FileLoader` + `SyntaxHighlighter` — different concerns |
| `validate(_ input:)` + `sanitize(_ input:)` — sequential pipeline | `PDFRenderer` + `FileWatcher` — unrelated responsibilities |
| A type and its immediate helper extension | Two unrelated utility functions |

---

## Swift Rules

**SW-1 — Modern concurrency only**
Use `async/await`, `Task`, `AsyncStream`, and `actors`. Do not write new completion-handler-based async code or bare `DispatchQueue.async` calls for business logic.

Enforce strict data isolation: mark all UI-updating classes and views with `@MainActor`. Any data model passed across a background `Task` boundary must conform to `Sendable`. Failing to do this produces actor-isolation compiler errors in Swift 6 strict concurrency mode.

| Do | Don't |
|---|---|
| `let data = try await loadFile(url)` | `loadFile(url) { data in … }` |
| `Task { await refresh() }` | `DispatchQueue.global().async { self.refresh() }` |
| `AsyncStream` for terminal output | Callback chains for streaming data |
| `@MainActor class EditorViewModel` | Updating `@Published` properties from a background thread |
| `struct FileNode: Sendable` | Passing a non-`Sendable` type into a detached `Task` |

**SW-2 — Prevent retain cycles**
Use `[weak self]` in every escaping closure that captures `self`. After any refactor, audit the changed file for new cycles. The critical risk is long-lived and infinite-loop tasks — a terminal `AsyncStream` listener or file watcher that holds a strong `self` reference will never deallocate, silently inflating RAM for the lifetime of the app.

| Do | Don't |
|---|---|
| `Task { [weak self] in await self?.listenToTerminalStream() }` — infinite loop | `Task { await self.listenToTerminalStream() }` — permanent leak |
| `Task { [weak self] in await self?.update() }` — safe default | Assuming a Task will release `self` before the object is dismissed |
| `NotificationCenter.addObserver { [weak self] _ in … }` | Storing a strong self reference in an observer |

**SW-3 — SwiftUI first, AppKit only when necessary**
Build all layout and interaction in SwiftUI. Drop to `NSViewRepresentable` / `NSViewControllerRepresentable` only when SwiftUI cannot meet a hard performance requirement (terminal ANSI rendering, large attributed-text views). Document the reason at the call site.

**SW-4 — Swift Commenting & Documentation Conventions**
All code within Sputnik must adhere to strict commenting standards to support Xcode Quick Help and DocC generation:

* **Regular Inline Notes:** Use standard double forward-slashes (`//`). For multiline blocks, use nested `/* ... */` structures.
* **Documentation Blocks:** Use triple forward-slashes (`///`) paired with CommonMark Markdown formatting. 
* **Special Callouts:** Document parameters, returns, and failure errors explicitly using standard keywords.

```swift
/// Evaluates the current memory footprint of a panel workflow.
///
/// - Parameters:
///   - panel: The targeted module view boundary (e.g., `.terminal` or `.editor`).
///   - forcePurge: If `true`, flushes the scrollback buffer before analyzing.
/// - Returns: The footprint size calculated in Megabytes (MB).
/// - Throws: `SputnikError.hardwareAccessDenied` if the system blocks PTY polling.
```

---

## macOS Framework Rules

**MR-1 — PDFKit for all PDF work**
Use `PDFDocument`, `PDFView`, and `PDFPage` for rendering, selection, and outline parsing. Do not attempt custom PDF rendering or third-party PDF libraries.

**MR-2 — FileManager + FilePresenter for file system access**
Use `FileManager` for all file operations. Implement `NSFilePresenter` to watch for external changes (edits by other apps, Finder moves). Never poll the file system on a timer.

**MR-3 — Task Priority for background work**
Offload heavy tasks (PDF parsing, syntax highlighting, directory scanning) using `Task(priority:)`. Do not use `DispatchQueue` for new business logic — that conflicts with SW-1. Use `DispatchQueue` only when bridging a macOS API that has no async/await equivalent, and document the call site with a comment explaining why.

| Work type | Task Priority |
|---|---|
| User-triggered action (open file) | `.userInitiated` |
| Background indexing / parsing | `.utility` |
| Maintenance / cleanup | `.background` |

**MR-4 — Foundation Process for shell spawning**
Use `Foundation.Process` to launch and manage the Zsh subprocess. Set `executableURL`, environment, and working directory explicitly. Bind `standardInput`, `standardOutput`, and `standardError` directly to the PTY `FileHandle` created in MR-5 — do not assign a `Foundation.Pipe` here, as Pipe bypasses the PTY and breaks interactive terminal programs. Always terminate and nil out the process on cleanup.

**MR-5 — PTY system calls for terminal I/O**
Use `posix_openpt` → `grantpt` → `unlockpt` to open the pseudo-terminal master. Bridge Zsh's stdin/stdout through the PTY file descriptor, not through `Pipe`, so interactive programs (editors, pagers) work correctly. Handle PTY cleanup in `PTY Lifecycle Management` (module 7 spec).
