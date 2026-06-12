# ``SputnikApp``

Sputnik is a native macOS development environment that coordinates six concurrent views within a unified, crash-resistant, memory-efficient minimalist layout, with interactive help guides.

## Overview

Sputnik brings together everything a developer needs in a single window — a file tree for navigation, a multi-mode text editor, synchronized Markdown and HTML previews, a PDF viewer, and a fully integrated Zsh terminal — without the overhead of Electron or a web-based shell.

### The Six Panels

| Panel | Module | Responsibility |
|---|---|---|
| Project File Tree | FileTreeModule | Folder navigation, file operations, drag-and-drop |
| Text Editor | TextEditorModule | Text / Markdown / ASCII art / HTML editing with syntax highlighting |
| Markdown Preview | MarkdownPreviewModule | Live-rendered Markdown preview synced to the editor |
| PDF Viewer | PDFViewerModule | PDFKit rendering, table-of-contents sidebar, thumbnails |
| HTML Preview | HTMLPreviewModule | Live HTML preview synced to the editor |
| Zsh Terminal | TerminalModule | PTY-hosted Zsh with ANSI rendering and scrollback |

### Architecture

Sputnik is built as a multi-module Swift Package Manager project. Each panel is a self-contained SPM package with its own `Package.swift`. Cross-module communication flows exclusively through `AppState` and `InterPanelRouter` in the Foundation layer — modules never reach into each other's internals.

```
┌─────────────────────────────────────────────────────────┐
│                    SputnikApp.app                        │
│  (App-Sputnik/ — main target, wires all modules)        │
├─────────────────────────────────────────────────────────┤
│  FoundationModule  (2 Foundation/)                       │
│  ├── AppState + WindowState — global & per-window state  │
│  ├── SettingsStore — all user-configurable preferences   │
│  ├── InterPanelRouter — cross-module file/event routing  │
│  ├── AppDelegate — lifecycle, termination gate           │
│  └── Utilities — Keychain, ProcessMonitor, AI monitors   │
├──────────┬──────────┬──────────┬──────────┬──────────┬───┤
│ FileTree │ TextEditor│Markdown  │ PDF      │ HTML     │Trm│
│ Module   │ Module    │Preview   │Viewer    │Preview   │Mod │
│ (6)      │ (3)       │Module (4)│Module (5)│Module (8)│(7) │
└──────────┴───────────┴──────────┴──────────┴──────────┴───┘
```

### Apple Intelligence Integration

On macOS 15+, Sputnik's text editor supports Apple Intelligence Writing Tools (Proofread, Rewrite, Summarize) and provides on-device semantic document search via the NaturalLanguage framework. See `LocalSemanticSearch` and `EditorTextView` for details.

## Topics

### App Assembly

- ``SputnikApp``
- ``AppDelegate``
- ``ContentView``

### State Management

- ``AppState``
- ``WindowState``
- ``SettingsStore``
- ``DocumentSession``

### Cross-Module Communication

- ``InterPanelRouter``
- ``AppInterPanelRouter``

### Panels

- ``TextEditorModule``
- ``MarkdownPreviewModule``
- ``FileTreeModule``
- ``PDFViewerModule``
- ``HTMLPreviewModule``
- ``TerminalModule``
- ``ResourcesModule``

### Local AI

- ``LocalSemanticSearch``
- ``MainAIMonitor``
- ``SupportingAIMonitor``
- ``SupportingAIConfiguration``
