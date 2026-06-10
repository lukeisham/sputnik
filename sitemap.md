# Sputnik — ASCII Site Map

```
App_Sputnik/
├── 1 Setup/                                                ─── Scaffolding & meta
│   ├── Module Guides/                                      ─── One guide per module
│   │   ├── 2 Foundation/
│   │   │   ├── 2.0 App overview/
│   │   │   │   └── guide.md  ← (287 ln)
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
│   │   └── 9 Resources/
│   │       ├── 9.1 ASCII Library/
│   │       │   └── guide.md
│   │       ├── 9.2 ASCII Art Help/
│   │       │   └── guide.md
│   │       ├── 9.3 Markdown Help/
│   │       │   └── guide.md
│   │       ├── 9.4 Html Help/
│   │       │   └── guide.md
│   │       └── 9.5 Grammar Help/
│   │           └── guide.md
│   ├── Plans Completed/                                    ─── *.md  ← 23 plan(s)
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
│   │   └── 2026-06-10 7 Terminal Input focus and live resize wiring.md
│   ├── Plans New/                                          ─── *.md  ← 2 plan(s)
│   │   ├── 2026-06-10 3 Text Editor Wire document lifecycle and editor UI.md
│   │   └── 2026-06-10 9 Resources Image display across previews and PDF viewer.md
│   ├── References/
│   │   ├── Issues.md  ← Known issues log
│   │   ├── module-template.md
│   │   └── plan-template.md
│   ├── SKILLS/                                             ─── Agent skill prompts
│   │   ├── !CreateAModuleGuide/
│   │   │   └── skill.md  ← skill.md
│   │   ├── !GenerateAPlan/
│   │   │   └── skill.md  ← skill.md
│   │   ├── !GrillMeWithContext/
│   │   │   └── skill.md  ← skill.md
│   │   └── !TrackIssues/
│   │       └── skill.md  ← skill.md
│   └── Vibe_Coding_Rules.md
├── 2 Foundation/                                            ─── CORE — Comms, state, settings, UI, persistence, lifecycle, utils
│   ├── 2.0 App Overview/
│   │   └── SputnikCommands.swift  ← (412 ln)
│   ├── 2.1 Inter-Panel communication/
│   │   ├── AppInterPanelRouter.swift
│   │   ├── FileType.swift
│   │   ├── InterPanelRouter.swift
│   │   └── PanelEvent.swift
│   ├── 2.2 Global State Management/
│   │   ├── AppState.swift  ← (241 ln)
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
│   │   ├── SettingsStore.swift  ← (361 ln)
│   │   ├── SupportingAIConfiguration.swift
│   │   ├── SupportingAISettingsView.swift  ← (212 ln)
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
│   │   ├── SlashCommandPopup.swift  ← (201 ln)
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
│   │   ├── SputnikMenuBarController.swift
│   │   └── TerminalLifecycle.swift
│   ├── 2.7 Utilities/
│   │   ├── ClosureMenuItem.swift
│   │   ├── CompletionProviding.swift
│   │   ├── DebounceTimer.swift
│   │   ├── HelpContextResolving.swift
│   │   ├── KeychainService.swift
│   │   ├── MainAIMonitor.swift  ← (291 ln)
│   │   ├── MoreContextMenu.swift
│   │   ├── ProcessMonitor.swift
│   │   ├── SlashCommand.swift
│   │   ├── SlashCommandRegistry.swift
│   │   └── SupportingAIMonitor.swift
│   └── Package.swift
├── 3 Text Editor/                                            ─── EDITOR — Multi-language text editing with ASCII art, Markdown, HTML
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
│   ├── 3.5 Spelling and Grammar Checking/
│   │   ├── GrammarAnnotation.swift
│   │   ├── QuickfixPopover.swift
│   │   ├── QuickfixPresenter.swift
│   │   ├── SpellCheckFileTypeGuard.swift
│   │   ├── SpellingCompletionProvider.swift
│   │   └── SpellingGrammarChecker.swift  ← (212 ln)
│   └── Package.swift
├── 4 Markdown Preview/                                            ─── MARKDOWN — Live-rendered preview synced to editor
│   ├── MarkdownPreviewCoordinator.swift
│   ├── MarkdownPreviewPanel.swift  ← (266 ln)
│   ├── MarkdownPreviewViewModel.swift
│   ├── MarkdownRenderView.swift
│   └── Package.swift
├── 5 PDF viewer/                                            ─── PDF — PDFKit rendering, TOC, thumbnails
│   ├── Package.swift
│   ├── PDFKitView.swift
│   ├── PDFToolbarView.swift
│   ├── PDFViewerPanel.swift
│   ├── PDFViewerViewModel.swift  ← (218 ln)
│   ├── ThumbnailsSidebarView.swift
│   └── TOCSidebarView.swift
├── 6 Project File Tree/                                            ─── FILE TREE — Folder tree, file ops, drag-and-drop
│   ├── FileContextMenu.swift
│   ├── FileSystemWatcher.swift
│   ├── FileTreeNode.swift
│   ├── FileTreePanel.swift  ← (235 ln)
│   ├── FileTreeRowView.swift
│   ├── FileTreeViewModel.swift  ← (268 ln)
│   └── Package.swift
├── 7 Terminal/                                            ─── TERMINAL — PTY-hosted Zsh with ANSI rendering
│   ├── ANSIParser.swift  ← (282 ln)
│   ├── KeyEncoder.swift
│   ├── Package.swift
│   ├── PTYHandle.swift
│   ├── ScreenCell.swift
│   ├── ScrollbackBuffer.swift
│   ├── TerminalEmulator.swift  ← (258 ln)
│   ├── TerminalManager.swift
│   ├── TerminalProfile.swift
│   ├── TerminalRenderer.swift
│   ├── TerminalSession.swift
│   ├── TerminalTextView.swift  ← (259 ln)
│   └── TerminalView.swift
├── 8 HTML Preview/                                            ─── HTML — Live WebKit preview synced to editor
│   ├── HTMLPreviewCoordinator.swift
│   ├── HTMLPreviewPanel.swift
│   ├── HTMLPreviewView.swift  ← (260 ln)
│   ├── LinkNavigationPolicy.swift
│   ├── Package.swift
│   └── SputnikImageSchemeHandler.swift
├── 9 Resources/                                            ─── ASSETS — ASCII library, help guides (4 topics), completions
│   ├── 9.1 ASCII Library/
│   │   ├── Arrows/
│   │   │   ├── corner_right_down.txt
│   │   │   ├── double_right.txt
│   │   │   ├── left_right.txt
│   │   │   ├── simple_right.txt
│   │   │   └── up_down.txt
│   │   ├── Decorative/
│   │   │   ├── diamond_row.txt
│   │   │   ├── floral_corner.txt
│   │   │   ├── heart_row.txt
│   │   │   ├── star_border.txt
│   │   │   └── wave_line.txt
│   │   ├── Dividers/
│   │   │   ├── dashed.txt
│   │   │   ├── dotted.txt
│   │   │   ├── double_line.txt
│   │   │   ├── single_line.txt
│   │   │   └── star_divider.txt
│   │   ├── Frames/
│   │   │   ├── double_box.txt
│   │   │   ├── rounded_box.txt
│   │   │   ├── shadow_box.txt
│   │   │   ├── single_box.txt
│   │   │   └── thick_box.txt
│   │   ├── Symbols/
│   │   │   ├── checkmark.txt
│   │   │   ├── heart.txt
│   │   │   ├── info.txt
│   │   │   ├── star.txt
│   │   │   └── warning.txt
│   │   ├── ASCIIArtRecord.swift
│   │   ├── ASCIILibrary.swift
│   │   ├── ASCIILibraryIndex.swift
│   │   └── index.json
│   ├── 9.2 ASCII art Help/
│   │   ├── basics/
│   │   │   ├── drawing-shapes.md
│   │   │   ├── getting-started.md
│   │   │   └── using-borders.md
│   │   ├── examples/
│   │   │   ├── cat-art.md
│   │   │   └── header-design.md
│   │   ├── techniques/
│   │   │   ├── arrows-and-direction.md
│   │   │   ├── decorative-patterns.md
│   │   │   ├── dividers-and-separators.md
│   │   │   ├── frames-and-boxes.md
│   │   │   └── symbols-and-icons.md
│   │   ├── ascii_art_help_index.json
│   │   ├── ascii_completions.json
│   │   ├── ASCIIArtHelpContent.swift
│   │   ├── ASCIIArtHelpCoordinator.swift
│   │   ├── ASCIIArtHelpIndex.swift
│   │   └── ASCIIArtHelpPanelView.swift  ← (254 ln)
│   ├── 9.3 Markdown Help/
│   │   ├── index.json
│   │   ├── markdown_completions.json
│   │   ├── MarkdownHelpContent.swift
│   │   ├── MarkdownHelpCoordinator.swift
│   │   ├── MarkdownHelpIndex.swift
│   │   └── MarkdownHelpPanelView.swift
│   ├── 9.4 Html Help/
│   │   ├── attributes/
│   │   │   ├── class-and-id.md
│   │   │   └── style.md
│   │   ├── elements/
│   │   │   ├── div-and-span.md
│   │   │   ├── forms.md
│   │   │   ├── headings.md
│   │   │   ├── images.md
│   │   │   ├── links.md
│   │   │   ├── lists.md
│   │   │   └── tables.md
│   │   ├── events/
│   │   │   └── onclick-and-events.md
│   │   ├── globals/
│   │   │   └── data-attributes.md
│   │   ├── guides/
│   │   │   └── best-practices.md
│   │   ├── html_completions.json
│   │   ├── html_help_index.json
│   │   ├── HTMLHelpContent.swift
│   │   ├── HTMLHelpCoordinator.swift
│   │   ├── HTMLHelpIndex.swift
│   │   └── HTMLHelpPanelView.swift
│   ├── 9.5 Grammar Help/
│   │   ├── edge-cases/
│   │   │   ├── collective-nouns.md
│   │   │   ├── conditional-sentences.md
│   │   │   ├── ending-with-prepositions.md
│   │   │   ├── irregular-plurals.md
│   │   │   ├── irregular-verbs.md
│   │   │   ├── singular-they.md
│   │   │   ├── split-infinitives.md
│   │   │   └── subjunctive-mood.md
│   │   ├── grammar/
│   │   │   ├── adjectives.md
│   │   │   ├── adverbs.md
│   │   │   ├── articles-a-an-the.md
│   │   │   ├── conjunctions.md
│   │   │   ├── dangling-modifiers.md
│   │   │   ├── gerunds-and-infinitives.md
│   │   │   ├── interjections.md
│   │   │   ├── prepositions.md
│   │   │   ├── pronouns.md
│   │   │   ├── subject-verb-agreement.md
│   │   │   └── verb-tense.md
│   │   ├── mechanics/
│   │   │   ├── abbreviations-and-acronyms.md
│   │   │   ├── capitalization-rules.md
│   │   │   └── writing-numbers.md
│   │   ├── punctuation/
│   │   │   ├── apostrophes.md
│   │   │   ├── colons.md
│   │   │   ├── commas.md
│   │   │   ├── dashes-and-hyphens.md
│   │   │   ├── parentheses-and-brackets.md
│   │   │   ├── quotation-marks.md
│   │   │   └── semicolons.md
│   │   ├── sentence-structure/
│   │   │   ├── clause-types.md
│   │   │   ├── diagramming-basics.md
│   │   │   ├── direct-and-indirect-objects.md
│   │   │   ├── phrase-types.md
│   │   │   ├── sentence-types.md
│   │   │   └── subject-and-predicate.md
│   │   ├── spelling/
│   │   │   ├── affect-vs-effect.md
│   │   │   ├── commonly-misspelled-words.md
│   │   │   ├── lose-vs-loose.md
│   │   │   ├── their-there-theyre.md
│   │   │   └── your-vs-youre.md
│   │   ├── style/
│   │   │   ├── active-vs-passive.md
│   │   │   ├── avoiding-cliches.md
│   │   │   ├── conciseness.md
│   │   │   ├── parallelism.md
│   │   │   ├── rhythm-and-flow.md
│   │   │   ├── sentence-variety.md
│   │   │   ├── tone-and-register.md
│   │   │   └── word-choice-and-colour.md
│   │   ├── usage/
│   │   │   ├── farther-vs-further.md
│   │   │   ├── fewer-vs-less.md
│   │   │   ├── i-e-vs-e-g.md
│   │   │   ├── lay-vs-lie.md
│   │   │   ├── that-vs-which.md
│   │   │   ├── then-vs-than.md
│   │   │   └── who-vs-whom.md
│   │   ├── GrammarHelpContent.swift
│   │   ├── GrammarHelpCoordinator.swift
│   │   ├── GrammarHelpIndex.swift
│   │   ├── GrammarHelpPanelView.swift
│   │   └── index.json
│   ├── 9.6 Preview Images/
│   │   └── PreviewImageResolver.swift
│   ├── Bundle+ResourcesModule.swift
│   ├── Package.swift
│   ├── SputnikCompletionCorpus.swift
│   ├── SputnikHelpContextResolver.swift
│   └── SputnikHelpPanel.swift  ← (408 ln)
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
    ├── ContentView.swift
    ├── Info.plist
    ├── Sputnik.entitlements
    └── SputnikApp.swift  ← (443 ln)
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
  Modules:         8  (2–9) + 1 Setup + 1 App target
  Swift files:   193  (18,060 lines total)
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
