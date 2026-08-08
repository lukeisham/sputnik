# Sudden Termination / Autosave Audit

**Date:** 2026-06-12
**Affected module:** 2 Foundation (2.6 App Lifecycle)
**Related plan:** Native niceties bundle

## Findings

### Termination gate (`applicationShouldTerminate`)
- ✅ Returns `.terminateNow` when there are no terminal managers (fast quit)
- ✅ Returns `.terminateLater` when PTYs are active, kills all PTYs via `withTaskGroup`, then replies `.terminateNow`
- ✅ All paths handled — `appState` nil check, empty managers check
- ✅ No force-unwraps

### Termination flush (`applicationWillTerminate`)
- ✅ Stops `ProcessMonitor` polling
- ✅ Flushes layout state via `persistenceService.flushLayout(layoutState)`
- ✅ Saves scratchpad text + docked width
- ✅ Flushes editor view states (caret position, scroll offset)
- ✅ Collects and saves window descriptors (frames, open tabs, active document)

### Data-loss window
- ✅ Editor autosaves periodically via `EditorViewModel`
- ✅ `applicationWillTerminate` provides the final synchronous flush
- ✅ No window between edit and flush that could lose data

### Impact of native-niceties changes
- Proxy icon (`representedURL`): purely cosmetic NSWindow property — no effect on termination
- Window tabbing (`allowsAutomaticWindowTabbing`): AppKit-level preference — no effect on termination
- Quick Look panel: dismissed by the system on termination — no effect
- Haptic feedback: stateless momentary API calls — no effect

## Verdict
✅ **No changes needed.** The termination gate and flush behaviour are correct and unaffected by this plan.
