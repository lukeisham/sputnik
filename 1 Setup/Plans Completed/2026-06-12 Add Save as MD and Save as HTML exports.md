# Plan: Add Save as .md and Save as .html Export Functions

**Date:** 2026-06-12
**Status:** Complete
**Modules touched:** 4 Markdown Preview, 8 HTML Preview
**Scope:** Additive only — no existing behaviour changed

---

## Goal

Add two new "Save as…" export actions:

1. **Save as Markdown… (.md)** — in the Markdown Preview panel's overflow (⋯) menu. Writes the active document's raw text to a user-chosen `.md` path.
2. **Save as HTML… (.html)** — in the HTML Preview panel's overflow (⋯) menu. Writes a fully-resolved HTML string (with F-4 CSS overrides stripped) to a user-chosen `.html` path.

Both are analogous to the existing "Save as PDF…" buttons in the same menus and follow the exact same structural pattern.

---

## Background

- "Save as PDF…" is already in both panels (Markdown Preview: `MarkdownPreviewPanel.swift:134`; HTML Preview: `HTMLPreviewPanel.swift:112`).
- The Markdown module has already assembled a rendered `NSAttributedString`; for a Markdown export we save the **source text**, not the render. This is intentional — the source is the canonical representation and it is already in memory as `appState.activeDocument?.text`.
- The HTML module's `HTMLPreviewView` already builds a fully-styled HTML string in `htmlByInjectingOverrides(...)`; for an HTML export we save the **source text** from the active session, not the injected-CSS variant. The user editing a `.html` file is the author of that HTML — they want their source back, not the F-4-modified version. If in the future a "render Markdown → export as HTML" path is desired, that is a separate feature.
- Both exports write plain UTF-8 text. No rendering pipeline is needed.
- Both follow SR-2 (handle all failure paths) and SR-4 (main thread only for UI, file write on a background Task with `.userInitiated` priority per MR-3).

---

## What is NOT changing

- The rendering pipelines in either module are untouched.
- The F-4 CSS-injection logic in `HTMLPreviewView` is untouched.
- `FileType`, `AppState`, `DocumentSession`, or any Foundation type — untouched.
- No new protocols, no new settings, no new module dependencies.

---

## Step-by-step Implementation

### Step 1 — Markdown Preview: add "Save as Markdown…" to the overflow menu

**File:** `4 Markdown Preview/MarkdownPreviewPanel.swift`

**What to add:**

Add a `@State private var saveAsMarkdownAction: (() -> Void)? = nil` alongside the existing `saveAsPDFAction` state variable.

Add the menu item in the overflow `Menu` block, immediately above "Save as PDF…":

```swift
Button("Save as Markdown…") { saveAsMarkdownAction?() }
    .disabled(saveAsMarkdownAction == nil)
```

Wire the action in `MarkdownRenderView`'s `updateNSView` (the same place `saveAsPDFAction` and `printAction` are wired — `MarkdownRenderView.swift` around line 191):

```swift
saveAsMarkdownAction = {
    guard let window = textView.window else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.text]          // .md has no UTType constant; .text opens the name field freely
    let baseName = (currentDocumentName as NSString).deletingPathExtension
    panel.nameFieldStringValue = baseName.isEmpty ? "document.md" : baseName + ".md"
    panel.beginSheetModal(for: window) { response in
        guard response == .OK, let url = panel.url else { return }
        Task(priority: .userInitiated) {
            do {
                try currentText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Save as Markdown Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}
```

`currentText` and `currentDocumentName` are captured from the active document at the time `updateNSView` runs — pass them into the closure as `let` captures, not as references through `appState`, so the closure is safe to call later.

**Binding thread:** `saveAsMarkdownAction` binding from `MarkdownRenderView` back to `MarkdownPreviewPanel` follows the same `@Binding var saveAsMarkdownAction: (() -> Void)?` pattern already used for `saveAsPDFAction`.

---

### Step 2 — HTML Preview: add "Save as HTML…" to the overflow menu

**File:** `8 HTML Preview/HTMLPreviewPanel.swift`

**What to add:**

Add `@State private var saveAsHTMLAction: (() -> Void)? = nil` alongside `saveAsPDFAction`.

Add the menu item immediately above "Save as PDF…":

```swift
Button("Save as HTML…") { saveAsHTMLAction?() }
    .disabled(saveAsHTMLAction == nil)
```

Wire the action in `HTMLPreviewView`'s `updateNSView` (around line 213, where `saveAsPDFAction` is wired):

```swift
context.coordinator.saveAsHTMLAction = { [weak webView] in
    guard let webView, let window = webView.window else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.html]
    let baseName = (coordinator.currentBaseURL?.deletingPathExtension().lastPathComponent) ?? "document"
    panel.nameFieldStringValue = baseName + ".html"
    panel.beginSheetModal(for: window) { [capturedText = sourceText] response in
        guard response == .OK, let url = panel.url else { return }
        Task(priority: .userInitiated) {
            do {
                try capturedText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Save as HTML Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}
saveAsHTMLAction = context.coordinator.saveAsHTMLAction
```

`sourceText` is captured at the time `updateNSView` runs from `session.text` (the raw, uninjected source). The coordinator gets a new `saveAsHTMLAction: (() -> Void)?` property, matching the existing pattern for `saveAsPDFAction` and `printAction`.

---

### Step 3 — Disabled state behaviour

Both actions are disabled when:
- No document is currently open (action closure is `nil` until wired by `updateNSView`, which guards on the session existing).
- The active document's file type does not match the panel (existing panel-level `.disabled` guards already cover this — the content area shows a placeholder, and `updateNSView` is not called).

No additional gating is needed.

---

### Step 4 — Verify

- [ ] Open a `.md` file in the editor. Markdown Preview panel visible. Open overflow menu → "Save as Markdown…" is enabled.
- [ ] Save to a new name. Confirm saved file contains the source text verbatim.
- [ ] Open a `.html` file in the editor. HTML Preview panel visible. Open overflow menu → "Save as HTML…" is enabled.
- [ ] Save to a new name. Confirm saved file contains the source HTML text (no F-4 injected CSS).
- [ ] Open a `.txt` file. Both buttons disabled in their respective panels' placeholders (or panels are absent).
- [ ] No document open. Both buttons disabled.
- [ ] File write failure (read-only volume) → NSAlert displayed, app does not crash.

---

## Files changed

| File | Change |
|---|---|
| `4 Markdown Preview/MarkdownPreviewPanel.swift` | Add `saveAsMarkdownAction` state; add menu item; thread binding to `MarkdownRenderView` |
| `4 Markdown Preview/MarkdownRenderView.swift` | Accept `saveAsMarkdownAction` binding; wire closure in `updateNSView` |
| `8 HTML Preview/HTMLPreviewPanel.swift` | Add `saveAsHTMLAction` state; add menu item; thread to `HTMLPreviewView` |
| `8 HTML Preview/HTMLPreviewView.swift` | Accept `saveAsHTMLAction` binding; wire closure in `updateNSView` |
| `8 HTML Preview/HTMLPreviewCoordinator.swift` | Add `saveAsHTMLAction: (() -> Void)?` property |

**No other files change.**

---

## Rules compliance

| Rule | Status |
|---|---|
| SR-1 — Modular design | ✅ Changes contained entirely within modules 4 and 8; no new cross-module dependencies |
| SR-2 — Error and crash proof | ✅ Both closures guard on window/session existence; file-write failures shown via NSAlert; no force-unwraps |
| SR-3 — Low RAM | ✅ No in-memory buffer is held; source text is captured at action-wire time (small UTF-8 string) |
| SR-4 — Fast and efficient | ✅ File write runs on `Task(priority: .userInitiated)`; NSAlert returned to `@MainActor` |
| SR-5 — macOS frameworks | ✅ `NSSavePanel`, `String.write(to:atomically:encoding:)` — all standard Foundation/AppKit |
| SR-6 — One responsibility per file | ✅ No new files; changes are narrow additions to existing files |
| SW-1 — Modern concurrency | ✅ `Task(priority:)` + `await MainActor.run` for alert |
| SW-2 — Retain cycles | ✅ `[weak webView]` capture in HTML closure; Markdown closure captures `textView` weakly |
| SW-3 — SwiftUI first | ✅ New UI is SwiftUI `Button` in existing `Menu` |
