# Sputnik — ASCII Site Map

```
App_Sputnik/
├── 1 Setup/                                                ─── Scaffolding & meta
│   ├── Guides/                                             ─── Additional guides
│   │   └── Testing.md
│   ├── Module Guides/                                      ─── One guide per module
│   │   ├── 2 Foundation/
│   │   │   ├── 2.0 App overview/
│   │   │   │   └── guide.md
│   │   │   ├── 2.1 Inter-panel communication/
│   │   │   │   └── guide.md
│   │   │   ├── 2.2 Global State Management/
│   │   │   │   └── guide.md
│   │   │   ├── 2.3 Settings/
│   │   │   │   └── guide.md
│   │   │   ├── 2.4 UI and UX/
│   │   │   │   └── guide.md
│   │   │   ├── 2.5 Persistence/
│   │   │   │   └── guide.md
│   │   │   ├── 2.6 App Lifecycle/
│   │   │   │   └── guide.md
│   │   │   └── 2.7 Utilities/
│   │   │       └── guide.md
│   │   ├── 3 Text Editor Window/
│   │   │   ├── 3.1 Text/
│   │   │   │   └── guide.md
│   │   │   ├── 3.2 Markdown Language/
│   │   │   │   └── guide.md
│   │   │   ├── 3.3 ASCII art/
│   │   │   │   └── guide.md
│   │   │   ├── 3.4 Html language/
│   │   │   │   └── guide.md
│   │   │   └── 3.5 Spelling and Grammar Check/
│   │   │       └── guide.md
│   │   ├── 4 Markdown Preview/
│   │   │   └── guide.md
│   │   ├── 5 PDF Viewer/
│   │   │   └── guide.md
│   │   ├── 6 Project File Tree/
│   │   │   └── guide.md
│   │   ├── 7 Terminal/
│   │   │   └── guide.md
│   │   ├── 8 HTML Preview/
│   │   │   └── guide.md
│   │   ├── 9 Resources/
│   │   │   ├── 9.1 ASCII Library/
│   │   │   │   └── guide.md
│   │   │   ├── 9.2 ASCII Art Help/
│   │   │   │   └── guide.md
│   │   │   ├── 9.3 Markdown Help/
│   │   │   │   └── guide.md
│   │   │   ├── 9.4 Html Help/
│   │   │   │   └── guide.md
│   │   │   ├── 9.5 Grammar Help/
│   │   │   │   └── guide.md
│   │   │   └── guide.md
│   │   └── 10 SputnikShared/
│   │       └── guide.md
│   ├── Plans Completed/                                    ─── *.md  ← 45 plan(s)
│   │   ├── 2026-06-08 2 Foundation Implement Foundation module source.md
│   │   ├── 2026-06-08 2 Foundation Multi-tab document model and preview sync.md
│   │   ├── 2026-06-08 2.0 App Overview Wire menu bar via SputnikCommands.md
│   │   ├── 2026-06-08 2.3 Settings Extend SettingsStore for editor and terminal.md
│   │   ├── 2026-06-08 3 Text Editor + 9 Resources Editor quickfix popover and context help.md
│   │   ├── 2026-06-08 3 Text Editor Implement Text Editor module source.md
│   │   ├── 2026-06-08 4 Markdown Preview Implement Markdown Preview module.md
│   │   ├── 2026-06-08 5 PDF Viewer Implement PDF Viewer module.md
│   │   ├── 2026-06-08 6 Project File Tree Implement Project File Tree module.md
│   │   ├── 2026-06-08 7 Terminal Implement Terminal module source.md
│   │   ├── 2026-06-08 8 HTML Preview Complete HTML Preview module.md
│   │   ├── 2026-06-08 9 Resources Complete build-out.md
│   │   ├── 2026-06-09 2 Foundation More Context shared lookup utility.md
│   │   ├── 2026-06-09 2 Foundation Multi-window and multi-project capacity.md
│   │   ├── 2026-06-09 2 Foundation Separate AI processes.md
│   │   ├── 2026-06-09 3 Text Editor Inline predictive autocomplete + granular assist settings.md
│   │   ├── 2026-06-09 8 HTML Preview Resolve ISS-010 JS security fix closeout.md
│   │   ├── 2026-06-09 Eight New Features.md
│   │   ├── 2026-06-09 Foundation-Resources Unify Help Navigation Route ISS-008.md
│   │   ├── 2026-06-09 SPM Build Wire-Up Plan.md
│   │   ├── 2026-06-10 2 Foundation Make project build ready.md
│   │   ├── 2026-06-10 2 Foundation Window and tab fixes.md
│   │   ├── 2026-06-10 3 Text Editor Wire document lifecycle and editor UI.md
│   │   ├── 2026-06-10 7 Terminal Input focus and live resize wiring.md
│   │   ├── 2026-06-10 9 Resources Image display across previews and PDF viewer.md
│   │   ├── 2026-06-11 2 Foundation Add stepped auto-complete debounce controls.md
│   │   ├── 2026-06-11 2 Foundation Close out ISS-023-028 Foundation compile fixes.md
│   │   ├── 2026-06-11 Foundation Polish — ErrorReporting actor + TestingSupport target + PreviewImageCache + RenderThrottle + guide updates.md
│   │   ├── 2026-06-11_ErrorReporting-wiring-into-AI-monitors.md
│   │   ├── 2026-06-11_Fix-open-issues-ISS-042-043-044-049.md
│   │   ├── 2026-06-11_Module-guide-updates-testing-and-closeout.md
│   │   ├── 2026-06-11_Update-Package-swift-for-TestingSupport.md
│   │   ├── 2026-06-11_Verify-and-mark-resolved-ISS-030-through-ISS-041.md
│   │   ├── 2026-06-11_Wire-PreviewImageCache-and-RenderThrottle.md
│   │   ├── 2026-06-12 Dynamic Panels Part 1 — Data Model and Persistence.md
│   │   ├── 2026-06-12 Extract loadAll() from SettingsStore.md
│   │   ├── 2026-06-12 File Tree quality-of-life features.md
│   │   ├── 2026-06-12 Fix EditorViewModel dependency injection and incremental highlighting.md
│   │   ├── 2026-06-12 Fix MarkdownPreviewViewModel PresentationIntent and file split.md
│   │   ├── 2026-06-12 Foundation Sendable sweep and utility extraction.md
│   │   ├── 2026-06-12 Make AppState Sendable-safe.md
│   │   ├── 2026-06-12 Terminal pasteboard integration.md
│   │   ├── Plan-Create-Testing-Skill.md
│   │   ├── Plan-Split-SputnikApp.md
│   │   └── Plan-Split-SputnikCommands.md
│   ├── Plans New/                                          ─── *.md  ← 2 plan(s)
│   │   ├── 2026-06-12 Dynamic Panels Part 2 — UI Shell.md
│   │   └── 2026-06-12 Dynamic Panels Part 3 — Drag Interactions and Cleanup.md
│   ├── References/
│   │   ├── Issues.md  ← Known issues log
│   │   ├── module-template.md
│   │   └── plan-template.md
│   ├── SKILLS/                                             ─── Agent skill prompts
│   │   ├── !CreateAModuleGuide/
│   │   │   └── skill.md
│   │   ├── !CreateTests/
│   │   │   └── skill.md
│   │   ├── !DiagnoseABug/
│   │   │   └── skill.md
│   │   ├── !EvaluateFeatureRequest/
│   │   │   └── skill.md
│   │   ├── !GenerateAPlan/
│   │   │   └── skill.md
│   │   ├── !GrillMeWithContext/
│   │   │   └── skill.md
│   │   ├── !TrackIssues/
│   │   │   └── skill.md
│   │   └── !UpdateGuides/
│   │       └── skill.md
│   └── Vibe_Coding_Rules.md
├── 2 Foundation/                                            ─── CORE — Comms, state, settings, UI, persistence, lifecycle, utils
│   ├── 2.0 App Overview/
│   │   ├── EditMenuGroup.swift
│   │   ├── FileMenuGroup.swift
│   │   ├── FormatMenuGroup.swift
│   │   ├── HelpMenuGroup.swift
│   │   ├── MenuHelpers.swift
│   │   ├── SputnikCommands.swift
│   │   ├── SputnikMenuGroup.swift
│   │   ├── ViewMenuGroup.swift
│   │   └── WindowMenuGroup.swift
│   ├── 2.1 Inter-Panel communication/
│   │   ├── AppInterPanelRouter.swift
│   │   ├── FileType.swift
│   │   ├── InterPanelRouter.swift
│   │   └── PanelEvent.swift
│   ├── 2.2 Global State Management/
│   │   ├── AppState.swift
│   │   ├── ContextUsage.swift
│   │   ├── DocumentSession.swift
│   │   ├── EditorCommandHandling.swift
│   │   ├── MainAIState.swift
│   │   ├── SupportingAIUsage.swift
│   │   ├── TerminalModelInfo.swift
│   │   └── WindowState.swift
│   ├── 2.3 Settings/
│   │   ├── AIConfiguration.swift
│   │   ├── AppTheme.swift
│   │   ├── AutoCompleteDebounceStep.swift
│   │   ├── EditorFont.swift
│   │   ├── ModelCapacity.swift
│   │   ├── SettingsStore.swift
│   │   ├── SupportingAIConfiguration.swift
│   │   ├── SupportingAISettingsView.swift
│   │   ├── TerminalColor.swift
│   │   └── WritingAssistMatrix.swift
│   ├── 2.4 UI and UX/
│   │   ├── AboutWindowView.swift
│   │   ├── DebounceStepPicker.swift
│   │   ├── DesignTokens.swift
│   │   ├── DocumentTabBar.swift
│   │   ├── DynamicPanelLayout.swift
│   │   ├── HelpTopic.swift
│   │   ├── PanelColumn.swift
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
│   │   ├── SettingsLoader.swift
│   │   └── WindowDescriptor.swift
│   ├── 2.6 App Lifecycle/
│   │   ├── AppDelegate.swift
│   │   ├── ContentView.swift
│   │   ├── SputnikMenuBarController.swift
│   │   └── TerminalLifecycle.swift
│   ├── 2.7 Utilities/
│   │   ├── ClosureMenuItem.swift
│   │   ├── CompletionProviding.swift
│   │   ├── HelpContextResolving.swift
│   │   ├── KeychainService.swift
│   │   ├── MainAIMonitor.swift
│   │   ├── MoreContextMenu.swift
│   │   ├── ProcessMonitor.swift
│   │   ├── SlashCommand.swift
│   │   ├── SlashCommandRegistry.swift
│   │   ├── SupportingAIMonitor.swift
│   │   └── TestingSupport.swift
│   └── Package.swift
├── 3 Text Editor/                                            ─── EDITOR — Multi-language text editing with ASCII art, Markdown, HTML
│   ├── 3.1 Text/
│   │   ├── CrashRecoveryStore.swift
│   │   ├── EditorCommandHandling.swift
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
│   │   ├── SyntaxHighlighter.swift
│   │   └── TextEditorPanel.swift
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
│   ├── 3.5 Spelling and Grammar Checking/
│   │   ├── GrammarAnnotation.swift
│   │   ├── QuickfixPopover.swift
│   │   ├── QuickfixPresenter.swift
│   │   ├── SpellCheckFileTypeGuard.swift
│   │   ├── SpellingCompletionProvider.swift
│   │   └── SpellingGrammarChecker.swift
│   └── Package.swift
├── 4 Markdown Preview/                                            ─── MARKDOWN — Live-rendered preview synced to editor
│   ├── MarkdownPreview+ParsedIntentKind.swift
│   ├── MarkdownPreviewCoordinator.swift
│   ├── MarkdownPreviewPanel.swift
│   ├── MarkdownPreviewRenderer.swift
│   ├── MarkdownPreviewViewModel.swift
│   ├── MarkdownRenderView.swift
│   └── Package.swift
├── 5 PDF viewer/                                            ─── PDF — PDFKit rendering, TOC, thumbnails
│   ├── Package.swift
│   ├── PDFKitView.swift
│   ├── PDFToolbarView.swift
│   ├── PDFViewerPanel.swift
│   ├── PDFViewerViewModel.swift
│   ├── ThumbnailsSidebarView.swift
│   └── TOCSidebarView.swift
├── 6 Project File Tree/                                            ─── FILE TREE — Folder tree, file ops, drag-and-drop
│   ├── FileContextMenu.swift
│   ├── FileSystemWatcher.swift
│   ├── FileTreeNode.swift
│   ├── FileTreePanel.swift
│   ├── FileTreeRowView.swift
│   ├── FileTreeViewModel.swift
│   └── Package.swift
├── 7 Terminal/                                            ─── TERMINAL — PTY-hosted Zsh with ANSI rendering
│   ├── ANSIParser.swift
│   ├── CellPosition.swift
│   ├── KeyEncoder.swift
│   ├── Package.swift
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
├── 8 HTML Preview/                                            ─── HTML — Live WebKit preview synced to editor
│   ├── HTMLPreviewCoordinator.swift
│   ├── HTMLPreviewPanel.swift
│   ├── HTMLPreviewView.swift
│   ├── LinkNavigationPolicy.swift
│   ├── Package.swift
│   └── SputnikImageSchemeHandler.swift
├── 9 Resources/                                            ─── ASSETS — ASCII library, help guides (4 topics), completions
│   ├── 9.6 Preview Images/
│   │   └── PreviewImageResolver.swift
│   ├── Sources/
│   │   ├── 9.1 ASCII Library/
│   │   │   ├── ASCIIArtRecord.swift
│   │   │   ├── ASCIILibrary.swift
│   │   │   └── ASCIILibraryIndex.swift
│   │   ├── 9.2 ASCII art Help/
│   │   │   ├── ASCIIArtHelpContent.swift
│   │   │   ├── ASCIIArtHelpCoordinator.swift
│   │   │   ├── ASCIIArtHelpIndex.swift
│   │   │   └── ASCIIArtHelpPanelView.swift
│   │   ├── 9.3 Markdown Help/
│   │   │   ├── MarkdownHelpContent.swift
│   │   │   ├── MarkdownHelpCoordinator.swift
│   │   │   ├── MarkdownHelpIndex.swift
│   │   │   └── MarkdownHelpPanelView.swift
│   │   ├── 9.4 Html Help/
│   │   │   ├── HTMLHelpContent.swift
│   │   │   ├── HTMLHelpCoordinator.swift
│   │   │   ├── HTMLHelpIndex.swift
│   │   │   └── HTMLHelpPanelView.swift
│   │   ├── 9.5 Grammar Help/
│   │   │   ├── GrammarHelpContent.swift
│   │   │   ├── GrammarHelpCoordinator.swift
│   │   │   ├── GrammarHelpIndex.swift
│   │   │   └── GrammarHelpPanelView.swift
│   │   ├── Bundle+ResourcesModule.swift
│   │   ├── SputnikCompletionCorpus.swift
│   │   ├── SputnikHelpContextResolver.swift
│   │   └── SputnikHelpPanel.swift
│   └── Package.swift
├── SputnikShared/                                            ─── SHARED — Cross-module utilities (ErrorReporting, caches, throttle)
│   ├── Sources/
│   │   ├── DebounceTimer.swift
│   │   ├── ErrorReporting.swift
│   │   ├── PreviewImageCache.swift
│   │   └── RenderThrottle.swift
│   └── Package.swift
└── App-Sputnik/                                            ─── macOS app target
    ├── Assets.xcassets/
    │   ├── AppIcon.appiconset/
    │   │   ├── AppIcon-128.png
    │   │   ├── AppIcon-128@2x.png
    │   │   ├── AppIcon-16.png
    │   │   ├── AppIcon-16@2x.png
    │   │   ├── AppIcon-256.png
    │   │   ├── AppIcon-256@2x.png
    │   │   ├── AppIcon-32.png
    │   │   ├── AppIcon-32@2x.png
    │   │   ├── AppIcon-512.png
    │   │   ├── AppIcon-512@2x.png
    │   │   └── Contents.json
    │   ├── SputnikLogo.imageset/
    │   │   ├── Contents.json
    │   │   ├── SputnikLogo.png
    │   │   └── SputnikLogo@2x.png
    │   ├── SputnikMenuBar.imageset/
    │   │   ├── Contents.json
    │   │   ├── SputnikMenuBar.png
    │   │   └── SputnikMenuBar@2x.png
    │   └── Contents.json
    ├── AppearanceTab.swift
    ├── ColumnDropDelegate.swift
    ├── ContentView.swift
    ├── DockedScratchpadPanel.swift
    ├── EditorTab.swift
    ├── Info.plist
    ├── SettingsHelpers.swift
    ├── SettingsView.swift
    ├── SpellingTab.swift
    ├── Sputnik.entitlements
    ├── SputnikApp.swift
    ├── TerminalTab.swift
    └── WindowRestorerView.swift
├── .gitignore
├── _gen_sitemap.py  ← Sitemap generator script
├── CLAUDE.md  ← Project guide / agent rules
├── LICENSE
├── notes.md  ← Scratch notes
├── Package.swift  ← Root SPM manifest
├── README.md  ← App spec & module breakdown
└── sitemap.md  ← This file

─────────────────────────────────────────────────────────────────
  SUMMARY
─────────────────────────────────────────────────────────────────
  Modules:         9  (2–9) + SputnikShared + 1 Setup + 1 App target
  Swift files:   193  (24,380 lines total)
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
                        └──────────────┬──────────────┘
                               │       │
                        ┌──────▼──┐  ┌─▼────────────┐
                        │  9 Res. │  │ SputnikShared │
                        │  (Help, │  │ (ErrorReport, │
                        │  ASCII) │  │  Cache, Timer)│
                        └─────────┘  └───────────────┘
```
