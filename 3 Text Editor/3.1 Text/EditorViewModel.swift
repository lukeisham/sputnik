import AppKit
import Foundation
import FoundationModule
import Observation
import ResourcesModule

// EditorViewModel — editor state + view state persistence

/// Centralised, thread-safe editor state for module 3.
///
/// All sub-modules in module 3 read or mutate this view model. Keeping the mode,
/// gating flags, and file URL here (not scattered across sub-modules) honours SR-1
/// ("module owns its state") and matches the module guides, which explicitly place
/// `htmlModeActive` and `spellCheckActive` in `EditorViewModel`.
@Observable
@MainActor
public final class EditorViewModel: EditorCommandHandling {

    // MARK: - Document identity

    /// The URL of the currently open file. `nil` for an untitled buffer.
    public var fileURL: URL?

    /// `true` when unsaved changes exist since the last clean file write.
    public var isDirty: Bool = false

    // MARK: - Undo

    /// The shared undo manager for the `NSTextView`. Wired in by `EditorView`.
    public var undoManager: UndoManager?

    // MARK: - Mode

    /// The active editing mode; drives syntax highlighting and sub-module activation.
    public var mode: EditorMode = .plainText

    // MARK: - Gating flags (set by sub-modules after per-file analysis)

    /// Set by `HTMLDocTypeGuard` when the open file begins with `<!DOCTYPE html>`.
    /// Enables HTML suggestions and the "Render as HTML" menu item (3.4).
    public var htmlModeActive: Bool = false

    /// `true` when the open file is a `.json` document (`modeForFileType` returns `.json`).
    /// Enables JSON suggestions, validation, and the "Render as JSON" menu item (3.6).
    public var jsonModeActive: Bool = false

    /// Structural errors from the last `JSONValidator` pass. Empty when the document is valid.
    /// Views observe this to show an error banner and underline.
    public var jsonValidationErrors: [JSONValidator.JSONError] = []

    /// Set by `SpellCheckFileTypeGuard` when the file extension is `.txt` or `.md`.
    /// Enables real-time spell/grammar checking (3.5).
    public var spellCheckActive: Bool = false

    // MARK: - Document loading

    /// The decoded text from the open file. Updated via `loadToken`.
    public var loadedText: String = ""

    /// UUID token bumped on each successful load. Prevents stale text from clobbering live edits.
    public var loadToken: UUID = UUID()

    /// The shared search controller. Wired in by `EditorView`.
    public var searchController: SearchController?

    /// The active NSTextView. Wired in by `EditorView` to support ASCII Studio.
    public var textView: NSTextView?

    /// The active NSScrollView that owns `textView`. Wired in by `EditorView`.
    /// Used by the minimap binder to observe scroll position.
    public var scrollView: NSScrollView?

    // MARK: - External file watching

    /// Watches the open file for external changes. Instantiated per document; cleared on close.
    private var fileWatcher: FileWatcher?

    /// `true` when the open file has been deleted or moved away externally.
    /// Views can observe this to disable save and show a "file gone" state.
    public var fileDeletedExternally: Bool = false

    /// Set when a background watcher operation fails and needs to surface a dialog.
    /// Views observe this to present the alert (e.g. `.alert` modifier keyed on this property).
    public var pendingAlert: SputnikAlert? = nil

    // MARK: - Dependencies (injected via init)

    private let appState: AppState
    private let persistenceService: PersistenceService

    /// Serializes editor buffer to recovery cache on text changes (ISS-036).
    private let recoveryStore: CrashRecoveryStore?

    /// Task for debouncing recovery writes (cancelled when a new write is scheduled).
    private var recoveryDebounceTask: Task<Void, Never>?

    /// The current user activity for the open document (Spotlight, Siri, Apple Intelligence context).
    /// Created when a file is opened; resigned when the document closes.
    private var userActivity: NSUserActivity?

    /// The inter-panel router, exposed for drag-and-drop and other actions.
    /// Read from the shared AppState.
    public var router: (any InterPanelRouter)? {
        appState.router
    }

    // MARK: - Interaction

    /// The interaction coordinator for special-element detection and auto-fill.
    public var interactionCoordinator: InteractionCoordinator?

    /// The `WritingAssistLanguage` corresponding to the current editor mode.
    public var interactionLanguage: WritingAssistLanguage {
        switch mode {
        case .markdown: return .markdown
        case .html: return .html
        case .json: return .json
        case .asciiArt: return .asciiArt
        case .plainText: return .markdown  // Default to markdown for plain text.
        }
    }

    // MARK: - Init

    public init(appState: AppState, persistenceService: PersistenceService) {
        self.appState = appState
        self.persistenceService = persistenceService
        self.recoveryStore = CrashRecoveryStore(persistence: persistenceService)
        appState.registerEditorCommandHandler(self)
    }

    // MARK: - Deinit

    // @MainActor deinit: guarantees cleanup runs on the main actor (same pattern as ISS-025,
    // MainAIMonitor). Eliminates the need for nonisolated(unsafe) on the three backing properties
    // and the nonisolated helpers that touch them (ISS-082).
    @MainActor
    deinit {
        stopWatchingFile()
        stopRecoveryWrite()
        resignUserActivity()
    }

    // MARK: - Document loading

    /// Opens and loads the file at the given URL. Validates encoding, infers mode,
    /// gates HTML and spell-check features, and updates `loadedText` and `loadToken`.
    /// On failure, sets no text and throws `SputnikAlert`.
    ///
    /// Runs `EncodingGuard` on a background task; publishes results on `@MainActor`.
    /// Sets up external file watching (ISS-033) and crash recovery (ISS-036).
    public func openDocument(_ url: URL?) async throws {
        // Stop watching and cancel recovery writes for the old file.
        stopWatchingFile()
        stopRecoveryWrite()

        guard let url = url else {
            resetForNewFile(url: nil)
            loadedText = ""
            loadToken = UUID()
            return
        }

        // Validate encoding and read file content off the main thread (ISS-081).
        // Both operations are pure I/O; Task.detached breaks @MainActor inheritance.
        let (_, text) = try await Task.detached(priority: .userInitiated) {
            let enc = try EncodingGuard.validate(url)
            let txt = try String(contentsOf: url, encoding: enc)
            return (enc, txt)
        }.value

        // Reset state and load the text.
        resetForNewFile(url: url)

        // Infer mode from file extension.
        let fileType = FileType(url: url)
        mode = modeForFileType(fileType)

        // Run gating checks.
        HTMLDocTypeGuard.check(text, viewModel: self)
        SpellCheckFileTypeGuard.check(url, viewModel: self)
        jsonModeActive = (fileType == .json)

        // Update text and bump token to notify `EditorView`.
        loadedText = text
        loadToken = UUID()

        // Register NSUserActivity for Spotlight, Siri Suggestions, and Apple Intelligence context.
        setUpUserActivity(for: url, mode: mode)

        // Start watching the file for external changes (ISS-033).
        startWatchingFile(url: url)
    }

    // MARK: - Helpers

    /// Resigns the current user activity and clears it.
    private func resignUserActivity() {
        userActivity?.resignCurrent()
        userActivity = nil
    }

    /// Creates and registers an NSUserActivity for the open document.
    /// Enables Spotlight indexing, Siri Suggestions, and Apple Intelligence context.
    private func setUpUserActivity(for url: URL, mode: EditorMode) {
        // Resign any previous activity first.
        resignUserActivity()

        let activity = NSUserActivity(activityType: "com.lukeisham.sputnik.editing")
        activity.title = url.lastPathComponent
        activity.userInfo = [
            "fileURL": url.absoluteString,
            "mode": mode.rawValue,
        ]
        activity.isEligibleForSearch = true
        activity.becomeCurrent()
        userActivity = activity
    }

    /// Resets all per-file state when a new file is opened.
    ///
    /// Mode is inferred by the caller from the file extension; reset to `.plainText`
    /// as a safe default so no sub-module is left active from the previous session.
    private func resetForNewFile(url: URL?) {
        resignUserActivity()
        fileURL = url
        isDirty = false
        fileDeletedExternally = false
        pendingAlert = nil
        htmlModeActive = false
        jsonModeActive = false
        jsonValidationErrors = []
        spellCheckActive = false
        mode = .plainText
    }

    /// Maps a `FileType` to an `EditorMode`.
    func modeForFileType(_ fileType: FileType) -> EditorMode {
        switch fileType {
        case .markdown: return .markdown
        case .html: return .html
        case .json: return .json
        case .ascii: return .asciiArt
        case .text, .pdf, .image, .binary, .unknown:
            return .plainText
        }
    }

    /// Starts watching the file at the given URL for external changes (ISS-033, ISS-111b).
    private func startWatchingFile(url: URL) {
        let watcher = FileWatcher(url: url)
        // Weak capture to avoid retain cycle (SW-2).
        watcher.onChanged = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.openDocument(url)
                } catch {
                    SputnikLogger.editor.error(
                        "Reload failed for \(url.lastPathComponent): \(error)")
                    self.pendingAlert = SputnikAlert.custom(
                        title: "Reload Failed",
                        message: error.localizedDescription
                    )
                    self.promptReloadFailed(url: url, error: error)
                }
            }
        }
        watcher.onDeleted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fileDeletedExternally = true
                self.promptFileDeleted(url: url)
            }
        }
        fileWatcher = watcher
    }

    /// Stops watching the current file.
    private func stopWatchingFile() {
        fileWatcher = nil  // FileWatcher.deinit cancels the DispatchSource and closes the fd.
    }

    /// Shows an alert when a background reload fails (ISS-112).
    @MainActor
    private func promptReloadFailed(url: URL, error: Error) {
        let alert = NSAlert()
        alert.messageText = "Reload Failed"
        alert.informativeText =
            "\"\(url.lastPathComponent)\" could not be reloaded.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Shows an alert when the open file is deleted or moved away externally (ISS-112).
    @MainActor
    private func promptFileDeleted(url: URL) {
        let alert = NSAlert()
        alert.messageText = "File Deleted"
        alert.informativeText =
            "\"\(url.lastPathComponent)\" was deleted or moved. Your unsaved buffer is still available — save it to a new location."
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Discard")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            // Route Save As through the menu handler's NSSavePanel flow.
            NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
        }
    }

    /// Schedules a debounced recovery write for the current document and text.
    /// Called by the Coordinator's `textDidChange` (ISS-036, SR-4).
    public func scheduleRecoveryWrite(text: String) {
        guard let fileURL else { return }
        recoveryDebounceTask?.cancel()
        recoveryDebounceTask = Task(priority: .userInitiated) { [weak self] in
            // 500ms debounce: wait for typing to pause before writing.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.recoveryStore?.scheduleWrite(for: fileURL, content: text)
        }
    }

    /// Cancels any pending recovery write.
    private func stopRecoveryWrite() {
        recoveryDebounceTask?.cancel()
        recoveryDebounceTask = nil
    }

    /// Clears the recovery cache after a successful save (called from Step 9).
    public func clearRecoveryCache() {
        guard let fileURL else { return }
        recoveryStore?.clearRecovery(for: fileURL)
    }

    // MARK: - Save / Save As (ISS-035)

    /// Saves the current buffer to the open file (atomic write off-main).
    /// Clears `isDirty`, suppresses the watcher's own-write notification, and clears recovery cache.
    public func save() async throws {
        guard let fileURL else {
            throw SputnikAlert.custom(title: "No File", message: "No file is open.")
        }

        // Suppress the watcher's notification of our own write (ISS-035, ISS-113).
        fileWatcher?.suppressOnce()

        // Snapshot @MainActor properties before entering the detached task (ISS-081).
        let text = loadedText
        let url = fileURL

        // Write off the main thread; Task.detached breaks @MainActor inheritance (ISS-081).
        // Safe-save: write to a sidecar temp file, then use replaceItemAt for an atomic
        // swap — if the process crashes between steps the original is never absent (ISS-083).
        try await Task.detached(priority: .userInitiated) {
            let tempURL = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".sputnik-tmp")
            try text.write(to: tempURL, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(
                url, withItemAt: tempURL,
                backupItemName: nil, options: [])
        }.value

        // Back on @MainActor after awaiting — no MainActor.run needed.
        isDirty = false
        fileDeletedExternally = false
        clearRecoveryCache()
        // Restart watcher so the fd tracks the new inode placed by replaceItemAt (ISS-111b).
        stopWatchingFile()
        startWatchingFile(url: url)
    }

    /// Saves the buffer to a user-selected file location.
    public func saveAs(to newURL: URL) async throws {

        // Snapshot @MainActor properties before entering the detached task (ISS-081).
        let text = loadedText

        // Write off the main thread; atomically:true uses rename(2) — already safe (ISS-081).
        try await Task.detached(priority: .userInitiated) {
            try text.write(to: newURL, atomically: true, encoding: .utf8)
        }.value

        // Back on @MainActor after awaiting — no MainActor.run needed.
        isDirty = false
        stopWatchingFile()
        fileURL = newURL
        clearRecoveryCache()
        startWatchingFile(url: newURL)
    }

    // MARK: - EditorCommandHandling protocol (steps 10–11)

    /// Triggers the Interaction action with the current detected special element.
    /// Called by the Edit menu "Interact with" item (⌘I) and right-click menu.
    public func triggerInteraction() {
        guard let coordinator = interactionCoordinator,
            let textView,
            let element = coordinator.detectedElement
        else { return }

        let selected = editorSelectionOrCurrentLine()
        let fullText = textView.string

        // Calculate the popup anchor rect from the selection.
        let selectionRect = selectionRectForPopup(textView: textView)

        coordinator.trigger(
            relativeTo: selectionRect,
            in: textView,
            selectedText: selected,
            fullText: fullText,
            language: interactionLanguage
        ) { [weak textView] newText, range in
            guard let textView else { return }
            if textView.shouldChangeText(in: range, replacementString: newText) {
                textView.replaceCharacters(in: range, with: newText)
                textView.didChangeText()
            }
        }
    }

    /// Returns the bounding rect of the current selection in the text view's coordinate space.
    private func selectionRectForPopup(textView: NSTextView) -> NSRect {
        let range = textView.selectedRange()
        guard let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else {
            return .zero
        }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range, actualCharacterRange: nil)
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return textView.convert(boundingRect, to: nil) ?? boundingRect
    }

    /// Opens the HTML Preview panel with the current file (⌘⌥P, File menu).
    /// Routes via the app's InterPanelRouter; no-op if HTML mode is inactive or no file is open.
    public func renderAsHTML() async throws {
        guard htmlModeActive, let url = fileURL else { return }
        await appState.router?.open(url)
    }

    /// Opens the JSON viewer panel (Module 8) with the current file (⌃⌘J, Edit > Render as...).
    /// No-op if JSON mode is inactive or no file is open.
    public func renderAsJSON() async throws {
        guard jsonModeActive, let url = fileURL else { return }
        await appState.router?.open(url)
    }

    /// Opens or raises the dockable ASCII Studio panel (⌘⌥A, Format menu).
    /// Instead of showing the old floating NSPanel, this toggles the .asciiStudio
    /// column in the dynamic layout.
    public func showASCIIStudio() async throws {
        appState.toggleColumn(renderMode: .asciiStudio)
    }

    /// Sends the editor's current text selection to the active terminal session.
    /// With nothing selected, sends the current line instead.
    public func sendSelectionToTerminal() {
        guard let router = appState.router else { return }
        let text = editorSelectionOrCurrentLine()
        guard !text.isEmpty else { return }
        router.sendToTerminal(text)
        router.focusTerminal()
    }

    /// Builds a shell command referencing the active document's file path
    /// (shell-escaped) and runs it in the active terminal.
    /// No-op when there is no active file.
    public func runCurrentFileInTerminal() {
        guard let router = appState.router,
            let url = fileURL
        else { return }
        let escaped = url.path.shellEscaped
        let command: String
        switch mode {
        case .markdown:
            command = "cat \(escaped)"
        case .html:
            command = "open \(escaped)"
        case .json:
            command = "cat \(escaped) | python3 -m json.tool"
        case .asciiArt:
            command = "cat \(escaped)"
        case .plainText:
            command = "cat \(escaped)"
        }
        router.runInTerminal(command)
        router.focusTerminal()
    }

    /// Inserts the terminal's current selected text at the editor cursor.
    public func insertTerminalSelection() {
        guard let router = appState.router,
            let text = router.terminalCurrentSelection(),
            let textView
        else { return }
        insertTextIntoEditor(text, at: textView)
    }

    /// Inserts the output of the last completed terminal command at the editor
    /// cursor. Falls back to terminal selection when no OSC 133 command output
    /// is available (integration not yet active, e.g. first prompt).
    public func insertLastCommandOutput() {
        guard let router = appState.router,
            let textView
        else { return }
        // Prefer exact command-output capture; degrade to selection.
        let text =
            router.terminalLastCommandOutput()
            ?? router.terminalCurrentSelection()
        guard let text else { return }
        insertTextIntoEditor(text, at: textView)
    }

    // MARK: - Private helpers for terminal integration

    /// Returns the selected text in the editor, or the current line if nothing
    /// is selected. Empty on an empty editor.
    private func editorSelectionOrCurrentLine() -> String {
        guard let textView else { return "" }
        let range = textView.selectedRange()
        let nsString = textView.string as NSString
        if range.length > 0 {
            return nsString.substring(with: range)
        }
        // Fall back to current line.
        let currentLineRange = nsString.lineRange(for: range)
        let line = nsString.substring(with: currentLineRange)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inserts the given text at the editor cursor, replacing any selected range.
    private func insertTextIntoEditor(_ text: String, at textView: NSTextView) {
        let range = textView.selectedRange()
        if textView.shouldChangeText(in: range, replacementString: text) {
            textView.replaceCharacters(in: range, with: text)
            textView.didChangeText()
        }
    }

    // MARK: - View state persistence

    /// Flushes the current caret position and scroll offset into the given
    /// `WindowState`'s `documentViewStates`, keyed by the active document's id.
    ///
    /// Reads from the live `NSTextView` so the values reflect the last visible
    /// position before termination, not a stale snapshot.
    @MainActor
    public func revealLine(_ line: Int) {
        guard let textView,
            let storage = textView.textStorage
        else { return }
        let text = storage.string as NSString
        var lineCount = 0
        var offset = 0
        while offset < text.length && lineCount < line {
            let lineRange = text.lineRange(for: NSRange(location: offset, length: 0))
            offset = lineRange.upperBound
            lineCount += 1
        }
        guard offset <= text.length else { return }
        let range = NSRange(location: offset, length: 0)
        textView.scrollRangeToVisible(range)
        textView.setSelectedRange(range)
    }

    public func flushViewState(to windowState: WindowState?) {
        guard let windowState,
            let activeDoc = windowState.activeDocument,
            let textView
        else { return }

        let selectedRange = textView.selectedRange()
        let scrollOffset = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero

        let state = DocumentViewState(
            selectedRange: selectedRange,
            scrollOffset: scrollOffset
        )
        windowState.documentViewStates[activeDoc.id.uuidString] = state
    }

    /// Applies a previously saved view state (caret + scroll) to the text view.
    /// Called after a document is opened during window restoration.
    ///
    /// The scroll position is applied in a deferred block so layout completes
    /// before the scroll offset is set.
    @MainActor
    public func applyViewState(_ state: DocumentViewState) {
        guard let textView else { return }

        // Set the caret position.
        let range = state.selectedRange
        let clampedLocation = min(range.location, textView.string.count)
        let clampedLength = min(range.length, textView.string.count - clampedLocation)
        let clampedRange = NSRange(location: clampedLocation, length: clampedLength)
        textView.setSelectedRange(clampedRange)

        // Scroll to the saved offset after layout completes.
        let offset = state.scrollOffset
        DispatchQueue.main.async {
            self.textView?.enclosingScrollView?.contentView.scroll(to: offset)
        }
    }
}
