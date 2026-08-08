# Plan: Verify and Mark Resolved — ISS-030 through ISS-041

**Date:** 2026-06-11  
**Module:** 3 Text Editor Window (3.1 Text, 3.3 ASCII, 3.4 HTML, 3.5 Spelling)  
**Status:** Complete  

---

## Overview

Audit all 12 open issues in the Module 3 range (ISS-030–ISS-041). Initial source-code review suggests every feature described in these issues has already been implemented and wired — the Issues.md status has simply not been updated. The plan is to confirm each fix by reading the code, then update Issues.md.

---

## Issues & Verification Results

### ISS-030 — Opening a document never loads contents into the editor

**Claim:** `EditorViewModel.resetForNewFile(url:)` resets flags but never reads the file or sets the `NSTextView` string.

**Verification:**
- `EditorViewModel.openDocument(_:)` at line 102 of `EditorViewModel.swift` reads the file via `String(contentsOf:encoding:)` (line 120), calls `resetForNewFile(url:)` (line 123), infers mode (line 127), runs gating checks (lines 130–131), then sets `loadedText` (line 134) and bumps `loadToken` (line 135).
- `ContentView.swift` line 52 calls `Task { try? await editorViewModel.openDocument(appState.activeDocument?.url) }` on `activeDocumentID` change.
- `EditorView.updateNSView` (lines 122–131) watches `loadToken` and applies `loadedText` to `NSTextView.string`.

**Result:** ✅ **Resolved**

---

### ISS-031 — `EncodingGuard` never called

**Claim:** No code path runs `EncodingGuard` before loading a file.

**Verification:**
- `EditorViewModel.openDocument(_:)` line 115–117 runs `EncodingGuard.validate(url)` in a `Task(priority: .userInitiated)` and unwraps the encoding. The task is awaited so the encoding is validated before the file is read on line 120.

**Result:** ✅ **Resolved**

---

### ISS-032 — `SyntaxHighlighter` never invoked

**Claim:** `EditorView.Coordinator.textDidChange` never calls `SyntaxHighlighter`.

**Verification:**
- `EditorView.updateNSView` lines 128–131: creates a `SyntaxHighlighter` on the `textStorage` and calls `.highlight(mode:)` immediately on initial load.
- `Coordinator.textDidChange` lines 200–204: debounced highlight pass (300ms) triggered for every text change when mode is not `.plainText`.

**Result:** ✅ **Resolved**

---

### ISS-033 — `FileWatcher` never instantiated

**Claim:** No `NSFilePresenter` is created for the open document.

**Verification:**
- `EditorViewModel.openDocument(_:)` line 138 calls `startWatchingFile(url:)`.
- `startWatchingFile` (lines 167–176) creates a `FileWatcher(url:)`, sets an `onReload` callback (weak self), and stores it in `fileWatcher`.
- `stopWatchingFile()` is called before opening a new document and in `deinit`.

**Result:** ✅ **Resolved**

---

### ISS-034 — `SearchBarView` never mounted

**Claim:** ⌘F toggles `SearchController.isVisible` but nothing observes it or renders the bar.

**Verification:**
- `SearchBarView` is mounted in `TextEditorPanel.body` lines 48–50, gated by `if let search = viewModel.searchController`.
- `SearchBarView` itself gates on `if controller.isVisible` (line 17).
- `SearchController` is created in `EditorView.makeNSView` line 53.
- `EditorTextView.keyDown(with:)` lines 58–63 intercepts ⌘F and calls `searchController?.toggleVisible()`.
- `viewModel.searchController = search` is set at line 105.

**Result:** ✅ **Resolved**

---

### ISS-035 — Save / Save As not implemented

**Claim:** No code to write the editor buffer back to disk.

**Verification:**
- `EditorViewModel.save()` (lines 212–235): atomic write to temp file then swap. Suppresses watcher. Clears `isDirty` and recovery cache.
- `EditorViewModel.saveAs(to:)` (lines 238–256): writes to new URL, updates `fileURL`, swaps watcher.
- Both are part of `EditorCommandHandling` protocol. Menu items "Save" (⌘S) and "Save As…" (⇧⌘S) call through `appState.editorCommandHandler` in `SputnikCommands.swift` (lines 134–152).
- Registration happens in `EditorViewModel.init()` via `appState.registerEditorCommandHandler(self)`.

**Result:** ✅ **Resolved**

---

### ISS-036 — `CrashRecoveryStore` never instantiated

**Claim:** The store exists but is never instantiated, so no recovery cache is written.

**Verification:**
- `EditorViewModel.recoveryStore` lazy property (lines 65–71) creates a `CrashRecoveryStore(persistence:)` on first access.
- `Coordinator.textDidChange` line 218 calls `viewModel.scheduleRecoveryWrite(text:)`.
- `scheduleRecoveryWrite` (lines 185–194) debounces 500ms then calls `recoveryStore?.scheduleWrite(for:content:)`.
- `stopRecoveryWrite()` and `clearRecoveryCache()` are called appropriately.

**Result:** ✅ **Resolved**

---

### ISS-037 — No mode-picker, mode stuck at `.plainText`

**Claim:** No mode-picker UI exists and `EditorViewModel.mode` is only set to `.plainText`.

**Verification:**
- Mode picker (`Picker("Editor Mode", selection: $viewModel.mode)`) is rendered in `TextEditorPanel` lines 33–39 with a segmented control over `EditorMode.allCases`.
- `EditorViewModel.modeForFileType(_:)` (lines 156–163) maps `FileType` → `EditorMode` (`.markdown`, `.html`, `.asciiArt`, `.plainText`).
- Called in `openDocument` line 127 after file is validated.

**Result:** ✅ **Resolved**

---

### ISS-038 — `HTMLDocTypeGuard` never called

**Claim:** `EditorViewModel.htmlModeActive` is always `false`.

**Verification:**
- `EditorViewModel.openDocument(_:)` line 130 calls `HTMLDocTypeGuard.check(text, viewModel: self)`.

**Result:** ✅ **Resolved**

---

### ISS-039 — `SpellCheckFileTypeGuard` never called

**Claim:** `EditorViewModel.spellCheckActive` is always `false`.

**Verification:**
- `EditorViewModel.openDocument(_:)` line 131 calls `SpellCheckFileTypeGuard.check(url, viewModel: self)`.

**Result:** ✅ **Resolved**

---

### ISS-040 — `RenderAsHTMLCommand` never inserted into menu

**Claim:** The command exists but is never wired to the menu.

**Verification:**
- "Render as HTML" button (⌘⌥P) is in `SputnikCommands` File menu at lines 156–168.
- Calls `appState.editorCommandHandler?.renderAsHTML()` (delegating to `EditorViewModel.renderAsHTML()` lines 262–268).
- `RenderAsHTMLCommand` class exists for `NSMenuItem` validation but the actual menu entry uses the protocol path via `EditorCommandHandling`, which is equivalent.

**Result:** ✅ **Resolved**

---

### ISS-041 — `ASCIIStudioPanel` never triggered

**Claim:** No menu item or shortcut presents the panel.

**Verification:**
- "ASCII Studio" button (⌘⌥A) is in `SputnikCommands` Format menu at lines 338–349.
- Calls `appState.editorCommandHandler?.showASCIIStudio()` (delegating to `EditorViewModel.showASCIIStudio()` lines 272–275).

**Result:** ✅ **Resolved**

---

## Summary

| ID | Module | Type | Claimed Issue | Actual Status |
|---|---|---|---|---|
| ISS-030 | 3.1 Text | Bug | Document loading broken | ✅ Resolved — `openDocument` reads file, sets `loadedText`/`loadToken` |
| ISS-031 | 3.1 Text | Missing Feature | `EncodingGuard` uncalled | ✅ Resolved — called in `openDocument` line 116 |
| ISS-032 | 3.1 Text | Missing Feature | `SyntaxHighlighter` uncalled | ✅ Resolved — initial pass in `updateNSView`, debounced in `textDidChange` |
| ISS-033 | 3.1 Text | Missing Feature | `FileWatcher` uninstantiated | ✅ Resolved — started/stopped in `openDocument`/`deinit` |
| ISS-034 | 3.1 Text | Missing Feature | `SearchBarView` unmounted | ✅ Resolved — mounted in `TextEditorPanel`, ⌘F toggle in `EditorTextView` |
| ISS-035 | 3.1 Text | Missing Feature | Save / Save As missing | ✅ Resolved — `save()`/`saveAs(to:)` with atomic write, menu items wired |
| ISS-036 | 3.1 Text | Missing Feature | `CrashRecoveryStore` uninstantiated | ✅ Resolved — lazy store, debounced write in `textDidChange` |
| ISS-037 | 3.1 Text | Missing Feature | No mode picker | ✅ Resolved — segmented picker in `TextEditorPanel`, `modeForFileType` |
| ISS-038 | 3.4 HTML | Missing Feature | `HTMLDocTypeGuard` uncalled | ✅ Resolved — called in `openDocument` line 130 |
| ISS-039 | 3.5 Spelling | Missing Feature | `SpellCheckFileTypeGuard` uncalled | ✅ Resolved — called in `openDocument` line 131 |
| ISS-040 | 3.4 HTML | Missing Feature | `RenderAsHTMLCommand` unwired | ✅ Resolved — `EditorCommandHandling.renderAsHTML()` → File menu ⌘⌥P |
| ISS-041 | 3.3 ASCII | Missing Feature | `ASCIIStudioPanel` unwired | ✅ Resolved — `EditorCommandHandling.showASCIIStudio()` → Format menu ⌘⌥A |

All 12 issues are **confirmed resolved** in the current source code. The Issues.md "Status" column should be updated from "Open" to "Resolved — 2026-06-11: [brief summary]".
