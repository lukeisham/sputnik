---
plan: Shortcuts Intents and NLEmbedding Semantic Search
module: 2 Foundation, App-Sputnik (Intents extension target), 3 Text Editor (3.1 Text)
created: 2026-06-12
status: pending
related_issues: none
---

## Purpose
Expose Sputnik's core actions to Apple Intelligence via Shortcuts intents (P4), and add on-device semantic document search using NLEmbedding (P5) — both gated behind `#available(macOS 15.0, *)` checks.

## Success Condition
1. macOS Shortcuts app can discover and invoke Sputnik actions (New Document, Open File, Switch to Panel, Search Text)
2. Siri/Apple Intelligence can trigger these shortcuts
3. A "Search Documents Semantically" feature exists in the editor or file tree, using local embeddings
4. All features degrade gracefully on macOS 14

## Steps

- [ ] 1. **Create Intents extension target**
   What: Add a new target `SputnikIntents` to the root `Package.swift` (or as a separate SPM target). Define `INIntent` subclasses for each action: `NewDocumentIntent`, `OpenFileIntent`, `SwitchPanelIntent`, `SearchTextIntent`. Each intent defines parameters and a handler.
   Why: Apple Intelligence and Siri can only invoke app actions that are exposed as system Shortcuts. Without an Intents extension, Sputnik is invisible to the Shortcuts app and Apple Intelligence automation.

- [ ] 2. **Implement intent handlers**
   What: Create an `IntentHandler` that conforms to `NewDocumentIntentHandling`, `OpenFileIntentHandling`, etc. Each handler receives the intent parameters and routes the action through `AppState` and `InterPanelRouter`.
   Why: The Intents extension runs in a separate process — it needs a lightweight handler that communicates back to the main app through shared state or XPC.

- [ ] 3. **Register Intents in Info.plist**
   What: Add `INIntentsSupported` entries to `App-Sputnik/Info.plist` so the system knows which intents Sputnik handles. Or use `INPreferences` API to register at runtime.
   Why: Without this registration, the system won't route intent requests to Sputnik's Intents extension.

- [ ] 4. **Update App-Sputnik/Info.plist in Package.swift**
   What: The root `Package.swift` excludes `Info.plist` — ensure the Intents extension target includes its own `Info.plist` with the correct `NSExtensionPrincipalClass`.
   Why: SPM targets need explicit plist handling for Intents extensions to be discoverable at runtime.

- [ ] 5. **Add NLEmbedding-based semantic search service**
   What: In `2 Foundation/2.7 Utilities` (or a new `2.8 Local AI` sub-module), create a `LocalSemanticSearch` service that uses `NLEmbedding` to compute sentence embeddings for each open document's text, stores them in an in-memory cache keyed by document ID, and provides a `search(query:) -> [(DocumentSession, Float)]` method that ranks documents by cosine similarity.
   Why: Enables on-device semantic search across open documents — no network, no API key. Users can find "the document about networking" without matching exact keywords. NLEmbedding is a built-in macOS framework (SR-5).

- [ ] 6. **Wire semantic search into the editor**
   What: Add a "Search Documents…" command (⌘⇧F or similar) that presents a search field. On each keystroke, query `LocalSemanticSearch` and display ranked results. Clicking a result navigates to that document tab via `InterPanelRouter`.
   Why: Gives users a Spotlight-like experience within Sputnik's document set, powered entirely by on-device AI.

- [ ] 7. **Update module guides**
   What: Update `1 Setup/Module Guides/2 Foundation/2.7 Utilities/guide.md` (or create `2.8 Local AI/guide.md` if created) with the new service. Update `3.1 Text/guide.md` with the search command.
   Why: Module guides are the source of truth — new capabilities must be documented.

## Risks and Constraints
- Intents extension requires a separate target with its own `Info.plist` — SPM package targets for Intents can be tricky. May need to create an Xcode project or use a SPM `.executableTarget` with the correct plist configuration.
- `NLEmbedding` is available from macOS 10.15+ (far older than our deployment target) but sentence embeddings require macOS 14+ (which we already target) — no additional guard needed beyond `#available`.
- `NLEmbedding` models are ~300MB each (the default model is included with the OS) — they are lazy-loaded on first use and cached by the system. First call may be slow (~1-2 seconds).
- Semantic search over large documents (10MB+) could be slow — consider chunking and indexing strategies (SR-3, SR-4).
- The Intents extension runs in a sandboxed process — it cannot directly access `AppState`. Use `NSXPCConnection` or `INIntents` shared app group container for communication.

## Files Affected
- `Package.swift` — add `SputnikIntents` target with dependencies, add Intents framework
- `App-Sputnik/Info.plist` — add `INIntentsSupported` entries
- `2 Foundation/2.7 Utilities/LocalSemanticSearch.swift` — new file: embedding service
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — integrate semantic search
- `App-Sputnik/ContentView.swift` — wire semantic search UI
- `1 Setup/Module Guides/2 Foundation/2.7 Utilities/guide.md` — or new `2.8 guide.md`

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (Shortcuts discover Sputnik actions; semantic search returns ranked results; macOS 14 builds cleanly)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation] Shortcuts Intents and Semantic Search`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
