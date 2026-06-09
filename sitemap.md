# Sputnik — ASCII Site Map

```
App_Sputnik/
│
├── CLAUDE.md                        ← Project guide / agent rules
├── README.md                        ← App spec & module breakdown
├── LICENSE
├── Package.swift                    ← Root SPM manifest
├── sitemap.md                       ← This file
│
├── 1 Setup/                         ─── Scaffolding & meta
│   ├── Vibe_Coding_Rules.md
│   ├── Module Guides/               ─── One guide per module
│   │   ├── 2 Foundation/
│   │   ├── 3 Text Editor Window/
│   │   ├── 4 Markdown Preview/      guide.md
│   │   ├── 5 PDF Viewer/            guide.md
│   │   ├── 6 Project File Tree/     guide.md
│   │   ├── 7 Terminal/              guide.md
│   │   └── 8 HTML Preview/          guide.md
│   ├── SKILLS/                      ─── Agent skill prompts
│   │   ├── !CreateAModuleGuide/     skill.md
│   │   ├── !GenerateAPlan/          skill.md
│   │   ├── !GrillMeWithContext/     skill.md
│   │   └── !TrackIssues/            skill.md
│   ├── Plans Completed/             *.md  ← 18 completed plans
│   ├── Plans New/                   (empty)
│   └── References/
│       ├── Issues.md                ← Known issues log
│       └── module-template.md
│
├── 2 Foundation/                    ═══ CORE — Comms, state, settings, UI, persistence, lifecycle, utils
│   ├── Package.swift
│   ├── 2.0 App Overview/
│   │   └── SputnikCommands.swift            (496 ln)
│   ├── 2.1 Inter-Panel communication/
│   │   ├── AppInterPanelRouter.swift
│   │   ├── FileType.swift
│   │   ├── InterPanelRouter.swift
│   │   └── PanelEvent.swift
│   ├── 2.2 Global State Management/
│   │   ├── AppState.swift                   (293 ln)
│   │   ├── ContextUsage.swift
│   │   ├── DocumentSession.swift
│   │   ├── MainAIState.swift
│   │   ├── SupportingAIUsage.swift
│   │   ├── TerminalModelInfo.swift
│   │   └── WindowState.swift
│   ├── 2.3 Settings/
│   │   ├── AIConfiguration.swift
│   │   ├── AppTheme.swift
│   │   ├── EditorFont.swift
│   │   ├── ModelCapacity.swift
│   │   ├── SettingsStore.swift              (439 ln)
│   │   ├── SupportingAIConfiguration.swift
│   │   ├── SupportingAISettingsView.swift
│   │   ├── TerminalColor.swift
│   │   └── WritingAssistMatrix.swift
│   ├── 2.4 UI and UX/
│   │   ├── AboutWindowView.swift
│   │   ├── DesignTokens.swift
│   │   ├── DocumentTabBar.swift
│   │   ├── HelpTopic.swift
│   │   ├── PanelID.swift
│   │   ├── PanelLayout.swift
│   │   ├── PanelPosition.swift
│   │   ├── ScratchpadPanel.swift
│   │   ├── ScratchpadTextView.swift
│   │   ├── SlashCommandPopup.swift
│   │   ├── SputnikAlert.swift
│   │   ├── SputnikColor.swift
│   │   ├── SputnikError.swift
│   │   └── StatusBarView.swift
│   ├── 2.5 Persistence/
│   │   ├── FilePersistenceService.swift
│   │   ├── LayoutState.swift
│   │   ├── PersistenceService.swift
│   │   └── WindowDescriptor.swift
│   ├── 2.6 App Lifecycle/
│   │   ├── AppDelegate.swift
│   │   ├── ContentView.swift
│   │   ├── SputnikApp.swift                (505 ln)
│   │   ├── SputnikMenuBarController.swift
│   │   └── TerminalLifecycle.swift
│   └── 2.7 Utilities/
│       ├── ClaudeStatusLineReader.swift
│       ├── ClosureMenuItem.swift
│       ├── CompletionProviding.swift
│       ├── DebounceTimer.swift
│       ├── HelpContextResolving.swift
│       ├── KeychainService.swift
│       ├── MainAIMonitor.swift
│       ├── MoreContextMenu.swift
│       ├── ProcessMonitor.swift
│       ├── SlashCommand.swift
│       ├── SlashCommandRegistry.swift
│       ├── SupportingAIMonitor.swift
│       └── TerminalModelDetector.swift
│
├── 3 Text Editor/                  ═══ EDITOR — Multi-language text editing with ASCII art, Markdown, HTML
│   ├── Package.swift
│   ├── 3.1 Text/
│   │   ├── CrashRecoveryStore.swift
│   │   ├── EditorMode.swift
│   │   ├── EditorTextView.swift
│   │   ├── EditorView.swift
│   │   ├── EditorViewModel.swift
│   │   ├── EncodingGuard.swift
│   │   ├── FileWatcher.swift
│   │   ├── GhostTextOverlay.swift
│   │   ├── LineNumberRulerView.swift
│   │   ├── SearchBarView.swift
│   │   ├── SearchController.swift
│   │   └── SyntaxHighlighter.swift
│   ├── 3.2 Markdown Language/
│   │   └── MarkdownLanguageProvider.swift
│   ├── 3.3 ASCII art/
│   │   ├── ASCIIArtLanguageProvider.swift
│   │   ├── ASCIILibraryBrowser.swift
│   │   ├── ASCIIStudioPanel.swift
│   │   ├── ASCIIStudioView.swift
│   │   ├── BlockCompletion.swift
│   │   └── ImageToASCIIConverter.swift
│   ├── 3.4 HTML Langugage/
│   │   ├── HTMLDocTypeGuard.swift
│   │   ├── HTMLLanguageProvider.swift
│   │   └── RenderAsHTMLCommand.swift
│   └── 3.5 Spelling and Grammar Checking/
│       ├── GrammarAnnotation.swift
│       ├── QuickfixPopover.swift
│       ├── QuickfixPresenter.swift
│       ├── SpellCheckFileTypeGuard.swift
│       ├── SpellingCompletionProvider.swift
│       └── SpellingGrammarChecker.swift
│
├── 4 Markdown Preview/             ═══ MARKDOWN — Live-rendered preview synced to editor
│   ├── Package.swift
│   ├── MarkdownPreviewCoordinator.swift
│   ├── MarkdownPreviewPanel.swift          (300 ln)
│   ├── MarkdownPreviewViewModel.swift
│   └── MarkdownRenderView.swift
│
├── 5 PDF viewer/                   ═══ PDF — PDFKit rendering, TOC, thumbnails
│   ├── Package.swift
│   ├── PDFKitView.swift
│   ├── PDFToolbarView.swift
│   ├── PDFViewerPanel.swift
│   ├── PDFViewerViewModel.swift
│   ├── TOCSidebarView.swift
│   └── ThumbnailsSidebarView.swift
│
├── 6 Project File Tree/            ═══ FILE TREE — Folder tree, file ops, drag-and-drop
│   ├── Package.swift
│   ├── FileContextMenu.swift
│   ├── FileSystemWatcher.swift
│   ├── FileTreeNode.swift
│   ├── FileTreePanel.swift
│   ├── FileTreeRowView.swift
│   └── FileTreeViewModel.swift
│
├── 7 Terminal/                     ═══ TERMINAL — PTY-hosted Zsh with ANSI rendering
│   ├── Package.swift
│   ├── ANSIParser.swift                   (319 ln)
│   ├── KeyEncoder.swift
│   ├── PTYHandle.swift
│   ├── ScreenCell.swift
│   ├── ScrollbackBuffer.swift
│   ├── TerminalEmulator.swift
│   ├── TerminalManager.swift
│   ├── TerminalProfile.swift
│   ├── TerminalRenderer.swift
│   ├── TerminalSession.swift
│   ├── TerminalTextView.swift
│   └── TerminalView.swift
│
├── 8 HTML Preview/                 ═══ HTML — Live WebKit preview synced to editor
│   ├── Package.swift
│   ├── HTMLPreviewCoordinator.swift
│   ├── HTMLPreviewPanel.swift
│   ├── HTMLPreviewView.swift
│   └── LinkNavigationPolicy.swift
│
├── 9 Resources/                    ═══ ASSETS — ASCII library, help guides (4 topics), completions
│   ├── Package.swift
│   ├── SputnikCompletionCorpus.swift
│   ├── SputnikHelpContextResolver.swift
│   ├── SputnikHelpPanel.swift             (467 ln)
│   ├── 9.1 ASCII Library/
│   │   ├── ASCIIArtRecord.swift
│   │   ├── ASCIILibrary.swift
│   │   ├── ASCIILibraryIndex.swift
│   │   ├── index.json
│   │   ├── Arrows/         corner_right_down.txt, double_right.txt, left_right.txt, …
│   │   ├── Decorative/     diamond_row.txt, floral_corner.txt, heart_row.txt, …
│   │   ├── Dividers/       dashed.txt, dotted.txt, double_line.txt, …
│   │   ├── Frames/         double_box.txt, rounded_box.txt, shadow_box.txt, …
│   │   └── Symbols/        checkmark.txt, heart.txt, info.txt, star.txt, warning.txt
│   ├── 9.2 ASCII art Help/
│   │   ├── ASCIIArtHelpContent.swift
│   │   ├── ASCIIArtHelpCoordinator.swift
│   │   ├── ASCIIArtHelpIndex.swift
│   │   ├── ASCIIArtHelpPanelView.swift
│   │   ├── ascii_art_help_index.json
│   │   ├── ascii_completions.json
│   │   ├── basics/         getting-started.md, drawing-shapes.md, using-borders.md
│   │   ├── techniques/     arrows-and-direction.md, decorative-patterns.md, …
│   │   └── examples/       cat-art.md, header-design.md
│   ├── 9.3 Markdown Help/
│   │   ├── MarkdownHelpContent.swift
│   │   ├── MarkdownHelpCoordinator.swift
│   │   ├── MarkdownHelpIndex.swift
│   │   ├── MarkdownHelpPanelView.swift
│   │   ├── index.json
│   │   └── markdown_completions.json
│   ├── 9.4 Html Help/
│   │   ├── HTMLHelpContent.swift
│   │   ├── HTMLHelpCoordinator.swift
│   │   ├── HTMLHelpIndex.swift
│   │   ├── HTMLHelpPanelView.swift
│   │   ├── html_help_index.json
│   │   ├── html_completions.json
│   │   ├── elements/      headings.md, links.md, images.md, tables.md, …
│   │   ├── attributes/    class-and-id.md, style.md
│   │   ├── events/        onclick-and-events.md
│   │   ├── globals/       data-attributes.md
│   │   └── guides/        best-practices.md
│   └── 9.5 Grammar Help/
│       ├── GrammarHelpContent.swift
│       ├── GrammarHelpCoordinator.swift
│       ├── GrammarHelpIndex.swift
│       ├── GrammarHelpPanelView.swift
│       ├── index.json
│       ├── grammar/       adjectives.md, adverbs.md, conjunctions.md, …
│       ├── punctuation/   commas.md, semicolons.md, apostrophes.md, …
│       ├── sentence-structure/  clause-types.md, phrase-types.md, …
│       ├── spelling/      affect-vs-effect.md, commonly-misspelled-words.md, …
│       ├── style/         active-vs-passive.md, conciseness.md, …
│       ├── usage/         that-vs-which.md, who-vs-whom.md, …
│       ├── mechanics/     capitalization-rules.md, writing-numbers.md, …
│       └── edge-cases/    irregular-plurals.md, subjunctive-mood.md, …
│
└── App-Sputnik/                   ─── macOS app target
    ├── SputnikApp.swift                   (502 ln)
    ├── ContentView.swift
    ├── Info.plist
    ├── Sputnik.entitlements
    └── Assets.xcassets/
        ├── AppIcon.appiconset/     *.png (16×16 → 512×512@2x)
        ├── SputnikLogo.imageset/   SputnikLogo.png + @2x
        ├── SputnikMenuBar.imageset/ SputnikMenuBar.png + @2x
        └── Contents.json

─────────────────────────────────────────────────────────────────
  SUMMARY
─────────────────────────────────────────────────────────────────
  Modules:         8  (2–9) + 1 Setup + 1 App target
  Swift files:    150  (17,455 lines total)
  Executables:      1  (Sputnik.app)
  Help guides:      4  (ASCII art, Markdown, HTML, Grammar)
  ASCII library:    5  categories (Arrows, Decorative, Dividers, Frames, Symbols)
```

---

## Module Dependency Flow

```
  ┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
  │  Project     │────▶│  Text Editor     │────▶│  Markdown Prev.  │
  │  File Tree   │     │  (3 Text/MM/     │     │  (4)             │
  │  (6)         │     │   ASCII/HTML)    │     └────────┬─────────┘
  └──────────────┘     └───────┬──────────┘              │
                               │                         │
                               ▼                         ▼
  ┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
  │  Terminal    │     │  HTML Preview    │     │  PDF Viewer      │
  │  (7)         │     │  (8)             │     │  (5)             │
  └──────────────┘     └──────────────────┘     └──────────────────┘
         │                       │                       │
         └───────────────┬───────────────────────────────┘
                        ┌▼───────────────────────────┐
                        │   2 Foundation (Core)       │
                        │   ─ Router, State, Settings │
                        │   ─ Persistence, Lifecycle  │
                        │   ─ UI/UX, Utilities        │
                        └─────────────────────────────┘
                               │
                        ┌──────▼──────┐
                        │  9 Resources │
                        │  (Help,ASCII)│
                        └─────────────┘
```
