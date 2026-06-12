# ``FoundationModule``

The Foundation module is the shared backbone of Sputnik. It owns all inter-panel communication, global and per-window state, user-configurable settings, persistence, app lifecycle, and shared utilities.

## Overview

Foundation provides the primitives that every other module depends on — but it never imports those modules itself (SR-1). The dependency arrow is one-way: panels depend on Foundation, not the reverse.

### Sub-Modules

| Directory | Responsibility |
|---|---|
| `2.0 App Overview` | Menu bar commands (File, Edit, Format, View, Window, Help) |
| `2.1 Inter-Panel communication` | ``InterPanelRouter`` protocol + ``PanelEvent`` stream |
| `2.2 Global State Management` | ``AppState``, ``WindowState``, ``DocumentSession`` |
| `2.3 Settings` | ``SettingsStore``, ``WritingAssistMatrix``, ``EditorFont``, AI config |
| `2.4 UI and UX` | Panel layout, tab bar, status bar, scratchpad, alerts, design tokens |
| `2.5 Persistence`` | ``PersistenceService`` protocol + ``FilePersistenceService`` + ``SettingsLoader`` |
| `2.6 App Lifecycle` | ``AppDelegate``, ``SputnikMenuBarController`` |
| `2.7 Utilities` | Keychain, AI monitors, process monitor, semantic search, testing mocks |

## Topics

### State Management

- ``AppState`` — Window coordinator
- ``WindowState`` — Per-window state
- ``DocumentSession`` — Per-tab document model

### Settings

- ``SettingsStore`` — User-configurable preferences
- ``WritingAssistMatrix`` — Per-language × per-function toggle matrix
- ``EditorFont`` — Font name + size pair
- ``AppTheme`` — Light / dark / system
- ``SupportingAIConfiguration`` — AI provider configuration
- ``ModelCapacity`` — Context window lookup for known models

### Routing

- ``InterPanelRouter`` — Cross-module routing protocol
- ``AppInterPanelRouter`` — Concrete router implementation
- ``PanelEvent`` — Routing event stream
- ``FileType`` — File extension classifier

### AI Integration

- ``LocalSemanticSearch`` — On-device semantic search
- ``MainAIMonitor`` — Terminal AI session tracking
- ``SupportingAIMonitor`` — Resource-feature AI accounting
- ``MainAIState`` — Main AI model and usage data
- ``SupportingAIUsage`` — Supporting AI usage metrics

### Utilities

- ``KeychainService`` — Secure credential storage
- ``ProcessMonitor`` — RAM/CPU usage polling
- ``SlashCommandRegistry`` — Autocomplete command registry
- ``MoreContextMenu`` — Right-click help context builder
- ``ClosureMenuItem`` — Closure-backed NSMenuItem
- ``CompletionProviding`` — Protocol for text completions
- ``HelpContextResolving`` — Protocol for help-topic resolution
