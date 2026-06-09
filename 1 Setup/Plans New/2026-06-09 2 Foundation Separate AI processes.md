---
plan: Separate AI processes — Supporting AI + Main AI monitoring
module: 2 Foundation (2.2, 2.3, 2.4, 2.7)
created: 2026-06-09
status: pending
related_issues: ISS-015, ISS-016
---

## Purpose
Separate the app's AI concepts into two clearly scoped roles — a **Supporting AI** (API-key-backed service whose sole function is to power resource features: help lookups, completions, and More Context) and a **Main AI** (any AI the user loads into the terminal for editing files or taking computer actions) — so each role has its own configuration, monitoring, and display surface without ambiguity.

## Success Condition
- Settings window has a "Supporting AI" tab showing: provider selector (DeepSeek / Gemini / Local), API key field (Keychain-backed), model name, base URL, and live metrics (% context window used, tokens used since app opened).
- The status bar at the bottom of the window shows Main AI model name and context window when a Main AI is active in the terminal; shows `—` when none is detected.
- `AIConfiguration` and `aiConfig` are fully replaced by `SupportingAIConfiguration` / `supportingAIConfig` with no leftover generic names.
- `AppState.contextUsage` is split: `supportingAIUsage: SupportingAIUsage?` (cumulative, for Settings display) and `mainAIUsage: MainAIContextUsage?` (per-session, for status bar).
- Code comments and Module Guides confirm: Supporting AI is called only by resource-feature code paths (modules 3, 4, 8, 9); the Main AI is never configured in Sputnik settings.

---

## Design Boundaries (Non-Negotiable)

**Supporting AI**
- Sole function: back resource functionality (help guides, More Context lookup, auto-complete suggestions).
- Must never be invoked from a user-facing chat surface, the scratchpad, or any module other than the resource pipeline (modules 3, 4, 8, 9 via Foundation protocols).
- Configuration is fully owned by Foundation 2.3; no module reaches into the config directly.

**Main AI**
- Loaded by the user into the terminal — could be Claude Code CLI, an Ollama model, Gemini CLI, or any other AI tool.
- Sputnik does not configure, launch, or control the Main AI. It only monitors and displays state.
- The terminal (module 7) is the Main AI's sole action surface in Sputnik.
- `MainAIMonitor` is read-only from Sputnik's perspective: it observes terminal output to detect an active AI session, but never writes to the terminal on the AI's behalf.

---

## Steps

1. **Log ISS-015 and ISS-016 to Issues.md**
   What: Append both issues to `1 Setup/References/Issues.md`.
   Why: The plan requires renaming `AIConfiguration` and splitting `contextUsage` — both are design problems that need a traceable issue ID before the fix.
   ✅ Done.

2. **Introduce `SupportingAIProvider` and `SupportingAIConfiguration` (2.3)**
   What: Create `2 Foundation/2.3 Settings/SupportingAIConfiguration.swift`.
   - `SupportingAIProvider` enum: `.deepSeek`, `.gemini`, `.local`; `Codable Sendable`; each case has a `defaultBaseURL: URL` computed property (DeepSeek: `https://api.deepseek.com`, Gemini: `https://generativelanguage.googleapis.com`, local: `http://localhost:11434`).
   - `SupportingAIConfiguration: Codable Sendable` — fields: `provider: SupportingAIProvider`, `modelName: String`, `baseURL: URL?` (override; `nil` uses provider default); no API key field (key in Keychain only, service label `"com.sputnik.supportingAIKey"`).
   Why: Gives the supporting AI role a dedicated, self-documenting type, resolving ISS-015. Separating provider from base URL allows local models to be pointed at any port without changing the provider enum.

3. **Rename `AIConfiguration` usages to `SupportingAIConfiguration` (2.3)**
   What: Delete or empty `AIConfiguration.swift`; update `SettingsStore` — rename `aiConfig: AIConfiguration` → `supportingAIConfig: SupportingAIConfiguration`; update `AISettingsView` references; update `ModelCapacity` callsites; update `StatusBarView` (currently reads `SettingsStore.aiConfig.modelName` for the supporting AI display — this moves to `SupportingAIMonitor` as part of Step 7).
   Why: Resolves ISS-015. Every reference is now unambiguous.

4. **Introduce `SupportingAIUsage` (2.2)**
   What: Create `2 Foundation/2.2 Global State Management/SupportingAIUsage.swift`.
   - `SupportingAIUsage: Sendable` — `totalTokensSinceLaunch: Int`, `contextWindow: Int`, computed `percentUsed: Double` (capped at 100). Reset to zero on app launch; never persisted.
   - Add `supportingAIUsage: SupportingAIUsage?` to `AppState` — `nil` until the first Supporting AI call completes. Written on `@MainActor` by `SupportingAIMonitor`.
   Why: Resolves ISS-016 (splits `contextUsage`). Supporting AI token count is cumulative across all resource calls in a session; it accumulates rather than reflecting only the last call, which is the right semantic for a "tokens used since app opened" display.

5. **Introduce `MainAIContextUsage` and `MainAIState` (2.2)**
   What: Create `2 Foundation/2.2 Global State Management/MainAIState.swift`.
   - `MainAIContextUsage: Sendable` — `usedTokens: Int`, `contextWindow: Int`, computed `percent: Double`; mirrors the existing `ContextUsage` shape but is explicitly for the Main AI.
   - `MainAIState: Sendable` — `modelName: String`, `contextWindow: Int?` (from `ModelCapacity` if known, `nil` for unknown models), `usage: MainAIContextUsage?`.
   - Add `mainAIState: MainAIState?` to `AppState` — `nil` when no Main AI is active in the terminal. Written by `MainAIMonitor`.
   - Deprecate and remove `contextUsage: ContextUsage?` from `AppState`; update all existing consumers (status bar context-% segment) to read from `mainAIState?.usage` instead.
   Why: Resolves ISS-016. The Main AI's context usage is per-session and shown in the status bar — semantically separate from the Supporting AI's cumulative token count.

6. **Introduce `SupportingAIMonitor` (2.7)**
   What: Create `2 Foundation/2.7 Utilities/SupportingAIMonitor.swift`.
   - `SupportingAIMonitor: @Observable @MainActor` class.
   - Owns a `@MainActor` method `recordUsage(inputTokens: Int, outputTokens: Int, contextWindow: Int)` called by any resource feature after a Supporting AI API response.
   - Internally accumulates `totalTokensSinceLaunch` and writes a fresh `SupportingAIUsage` to `AppState.supportingAIUsage`.
   - `modelName: String` computed from `SettingsStore.supportingAIConfig.modelName`.
   - `reset()` — resets the accumulator to zero (called on app launch via `AppDelegate`; not called mid-session).
   - Created at app launch in `SputnikApp`, injected via `.environment(supportingAIMonitor)`.
   Why: Gives the Supporting AI role a single accountant for all resource calls. Resource-feature code only calls `recordUsage`; it does not touch `AppState` directly, so Foundation stays the sole writer (SR-1).

7. **Introduce `MainAIMonitor` (2.7)**
   What: Create `2 Foundation/2.7 Utilities/MainAIMonitor.swift`.
   - `MainAIMonitor: @Observable @MainActor` class.
   - Receives terminal output line-by-line via `observe(line: String)` (called by `TerminalSession` output listener — module 7 calls this through a Foundation protocol, not directly; see Step 9).
   - Detects known AI session markers: Claude Code status-line format (already implemented in F-8's terminal model detection), plus a simple heuristic for other AIs (e.g. Ollama prints model name on session start; Gemini CLI has a known prompt prefix).
   - When a session is detected, writes `MainAIState(modelName:contextWindow:usage:)` to `AppState.mainAIState` on `@MainActor`.
   - When the terminal session ends (or a `clear` / new shell is detected), sets `AppState.mainAIState = nil`.
   - `setManual(modelName: String)` — allows the user to declare a model manually (see Step 10); sets `AppState.mainAIState` with `contextWindow` looked up from `ModelCapacity`.
   - `updateUsage(usedTokens: Int, contextWindow: Int)` — updates `mainAIState?.usage` when Claude Code status-line metrics are received (F-8 path).
   Why: Centralises Main AI detection in one place per SR-1. `MainAIMonitor` is the sole writer of `AppState.mainAIState`. Terminal module 7 does not write `AppState` directly — it calls through the protocol defined in Step 9.

8. **Define `TerminalAIOutputObserving` protocol (2.1 / 2.7)**
   What: Add `TerminalAIOutputObserving` protocol to Foundation (`2 Foundation/2.7 Utilities/MainAIMonitor.swift` or a thin file in `2.1 Inter-panel communication`).
   ```swift
   /// Terminal module calls this when a new output line arrives, so Foundation can detect AI sessions.
   protocol TerminalAIOutputObserving: AnyObject {
       func observe(line: String)
   }
   ```
   - `MainAIMonitor` conforms to this protocol.
   - `SputnikApp` registers `mainAIMonitor` as the observer on the `TerminalSession` at launch.
   Why: Keeps SR-1 intact — module 7 (Terminal) must not import or call `MainAIMonitor` directly. The protocol is owned by Foundation; Terminal depends only on the protocol.

9. **Wire `MainAIMonitor` into `TerminalSession` (2.6 App Lifecycle / 7 Terminal)**
   What: In `SputnikApp` (2.6), after creating `mainAIMonitor` and `terminalSession`, set `terminalSession.aiOutputObserver = mainAIMonitor`. In `TerminalSession` (module 7), add `weak var aiOutputObserver: TerminalAIOutputObserving?`; call `aiOutputObserver?.observe(line:)` for each decoded output line inside the `AsyncStream` consumer. Use `[weak self]` on the observer (SW-2).
   Why: Completes the output-observation loop without creating a hard coupling between Terminal and Foundation's monitor implementation. The `weak` reference prevents `TerminalSession` from keeping `MainAIMonitor` alive.

10. **Add Manual Main AI declaration to status bar (2.4)**
    What: In `StatusBarView`, add a right-click / long-press context menu on the "Main AI" segment. Menu items: "Set model…" (opens a small `NSAlert`-style text entry for the model name) and "Clear" (sets `AppState.mainAIState = nil`). "Set model…" calls `mainAIMonitor.setManual(modelName:)`.
    Why: Not all AI CLIs emit parseable output. The user may run a local model with no detectable signature. Manual declaration is the safety net that ensures the display is always accurate.

11. **Update `SupportingAISettingsView` — add live metrics (2.3)**
    What: Rename `AISettingsView` → `SupportingAISettingsView`. Add a "Usage (this session)" section below the credentials:
    - Model name (read-only, from `supportingAIConfig.modelName`).
    - Context window % used (`AppState.supportingAIUsage?.percentUsed`, shown as a progress bar; hidden when `nil`).
    - Tokens used since launch (`AppState.supportingAIUsage?.totalTokensSinceLaunch`, formatted as `"12,340 tokens"`; hidden when `nil`).
    - Add provider picker (`.deepSeek` / `.gemini` / `.local`) that updates `supportingAIConfig.provider` and autofills the base URL field with the provider's default.
    Why: This is the display surface specified for Supporting AI metrics. Keeping it in Settings (not the status bar) is correct because Supporting AI metrics are operational detail, not the user's primary focus.

12. **Update `StatusBarView` to show Main AI state (2.4)**
    What: Replace the current single AI model-name segment (which reads `SettingsStore.aiConfig.modelName`) with two segments:
    - **Supporting AI segment** (left of the existing position): shown only when `supportingAIConfig.modelName` is non-empty; displays model name; no context % here (context % is in Settings).
    - **Main AI segment** (right of Supporting AI): shown only when `AppState.mainAIState != nil`; displays `mainAIState.modelName` and context window (e.g. `claude-sonnet-4-6  CTX 34%`); when context window is unknown (`contextWindow == nil`), shows model name only.
    Why: The status bar is the correct surface for Main AI visibility per the user's spec. Supporting AI is secondary — it stays in the status bar as a subtle indicator but does not show context %, which belongs in Settings.

13. **Extend `ModelCapacity` for non-Claude models (2.3)**
    What: Add static entries to `ModelCapacity.contextWindow(for:)` for known DeepSeek and Gemini models (e.g. `deepseek-chat`: 64 000, `deepseek-reasoner`: 64 000, `gemini-1.5-pro`: 1 048 576, `gemini-1.5-flash`: 1 048 576, `gemini-2.0-flash`: 1 048 576). Return `nil` for all unrecognised model names. Document each entry with its public spec source in a `///` comment.
    Why: `ModelCapacity` is the single lookup table for context window sizes (SR-1). Adding DeepSeek and Gemini models here means both `SupportingAIMonitor` and `MainAIMonitor` can compute context % for all supported providers without duplicating the table.

14. **Update Module Guides (2.2, 2.3, 2.4, 2.7)**
    What: Update guides for all four sub-modules to reflect:
    - 2.3: `SupportingAIConfiguration`, `SupportingAISettingsView`, `SupportingAIProvider`; document Supporting AI boundary rule.
    - 2.2: `supportingAIUsage`, `mainAIState`, `MainAIState`, `MainAIContextUsage`; remove `contextUsage`.
    - 2.4: `StatusBarView` two-segment AI display; `TerminalAIOutputObserving` protocol.
    - 2.7: `SupportingAIMonitor`, `MainAIMonitor`; add to "Known consumers" table.
    Why: Module Guides are the source of truth (CLAUDE.md). Any future agent reading a guide must see the correct design before touching code.

---

## Risks and Constraints

- **SR-1 — Do not let resource feature code call `AppState.mainAIState` or vice versa.** Supporting AI and Main AI are entirely separate data flows. If future code needs to "ask the Main AI something," that is out of scope for this plan and must be planned separately.
- **SW-2 — `MainAIMonitor` holds a reference to `AppState` and is observed by `TerminalSession` as a weak delegate.** Audit retain graph after wiring Step 9.
- **F-8 already detects Claude Code terminal output.** That detection code should be moved into `MainAIMonitor.observe(line:)` (or remain in module 7 and call the protocol) — it must not exist in two places (SR-1). Clarify ownership in Step 7.
- **`ModelCapacity` entries for third-party models may go stale** as providers update their context limits. Document a manual update process in the guide comment; this is acceptable given SR-5 (no third-party dependency to auto-fetch limits).
- **No third-party Swift packages** for API calls (SR-5). Supporting AI API calls use `URLSession` with `async/await` directly. The plan does not implement the API call layer — that belongs in a subsequent plan for whichever resource feature consumes it first.

---

## Files Affected

- `2 Foundation/2.3 Settings/SupportingAIConfiguration.swift` — new; replaces `AIConfiguration.swift`
- `2 Foundation/2.3 Settings/AIConfiguration.swift` — deleted or replaced with a deprecated typealias that points to `SupportingAIConfiguration` (choose at implementation time)
- `2 Foundation/2.3 Settings/SettingsStore.swift` — rename `aiConfig` → `supportingAIConfig`; type changed to `SupportingAIConfiguration`
- `2 Foundation/2.3 Settings/AISettingsView.swift` — renamed to `SupportingAISettingsView.swift`; add metrics section and provider picker
- `2 Foundation/2.3 Settings/ModelCapacity.swift` — add DeepSeek and Gemini entries
- `2 Foundation/2.2 Global State Management/AppState.swift` — add `supportingAIUsage`, `mainAIState`; remove `contextUsage`
- `2 Foundation/2.2 Global State Management/SupportingAIUsage.swift` — new
- `2 Foundation/2.2 Global State Management/MainAIState.swift` — new; contains `MainAIState`, `MainAIContextUsage`
- `2 Foundation/2.7 Utilities/SupportingAIMonitor.swift` — new
- `2 Foundation/2.7 Utilities/MainAIMonitor.swift` — new; contains `TerminalAIOutputObserving` protocol and `MainAIMonitor`
- `2 Foundation/2.4 UI and UX/StatusBarView.swift` — update to two-segment AI display
- `2 Foundation/2.6 App Lifecycle/SputnikApp.swift` — wire `MainAIMonitor` to `TerminalSession`; inject `SupportingAIMonitor` into environment
- `7 Terminal/TerminalSession.swift` — add `weak var aiOutputObserver: TerminalAIOutputObserving?`; call `observe(line:)` in output listener
- Module Guides: `2.2`, `2.3`, `2.4`, `2.7`

---

## Closeout

- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] ISS-015 and ISS-016 marked Resolved in Issues.md
- [ ] Changes committed: `[2 Foundation] Separate AI processes — Supporting AI + Main AI monitoring`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
