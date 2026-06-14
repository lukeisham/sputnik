import AppKit
import Foundation
import FoundationModule
import Observation

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

    // MARK: - External file watching

    /// Watches the open file for external changes. Instantiated per document; cleared on close.
    // nonisolated(unsafe): required for deinit access; written only from @MainActor and deinit (no concurrent access).
    private nonisolated(unsafe) var fileWatcher: FileWatcher?

    // MARK: - Dependencies (injected via init)

    private let appState: AppState
    private let persistenceService: PersistenceService

    /// Serializes editor buffer to recovery cache on text changes (ISS-036).
    private let recoveryStore: CrashRecoveryStore?

    /// Task for debouncing recovery writes (cancelled when a new write is scheduled).
    // nonisolated(unsafe): required for deinit access; written only from @MainActor and deinit (no concurrent access).
    private nonisolated(unsafe) var recoveryDebounceTask: Task<Void, Never>?

    /// The current user activity for the open document (Spotlight, Siri, Apple Intelligence context).
    /// Created when a file is opened; resigned when the document closes.
    // nonisolated(unsafe): required for deinit access; written only from @MainActor and deinit (no concurrent access).
    private nonisolated(unsafe) var userActivity: NSUserActivity?

    /// The inter-panel router, exposed for drag-and-drop and other actions.
    /// Read from the shared AppState.
    public var router: (any InterPanelRouter)? {
        appState.router
    }

    // MARK: - Init

    public init(appState: AppState, persistenceService: PersistenceService) {
        self.appState = appState
        self.persistenceService = persistenceService
        self.recoveryStore = CrashRecoveryStore(persistence: persistenceService)
        appState.registerEditorCommandHandler(self)
    }

    // MARK: - Deinit

    deinit {
        // nonisolated helpers — safe to call here because the three stored properties
        // they touch are nonisolated(unsafe) and deinit guarantees no concurrent access.
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
    /// nonisolated so it can be called safely from deinit (ISS-082).
    nonisolated private func resignUserActivity() {
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
        htmlModeActive = false
        spellCheckActive = false
        mode = .plainText
    }

    /// Maps a `FileType` to an `EditorMode`.
    private func modeForFileType(_ fileType: FileType) -> EditorMode {
        switch fileType {
        case .markdown: return .markdown
        case .html: return .html
        case .ascii: return .asciiArt
        case .text, .pdf, .image, .binary, .unknown:
            return .plainText
        }
    }

    /// Starts watching the file at the given URL for external changes (ISS-033).
    private func startWatchingFile(url: URL) {
        let watcher = FileWatcher(url: url)
        // Weak capture to avoid retain cycle (SW-2).
        watcher.onReload = { [weak self] in
            Task { @MainActor [weak self] in
                try? await self?.openDocument(url)
            }
        }
        fileWatcher = watcher
    }

    /// Stops watching the current file.
    /// nonisolated so it can be called safely from deinit (ISS-082).
    nonisolated private func stopWatchingFile() {
        fileWatcher = nil  // FileWatcher.deinit calls NSFileCoordinator.removeFilePresenter — thread-safe.
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
    /// nonisolated so it can be called safely from deinit; Task.cancel() is concurrency-safe (ISS-082).
    nonisolated private func stopRecoveryWrite() {
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

        // Suppress the watcher's notification of our own write (ISS-035).
        fileWatcher?.setSuppressNextChange()

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
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL,
                                                       backupItemName: nil, options: [])
        }.value

        // Back on @MainActor after awaiting — no MainActor.run needed.
        isDirty = false
        clearRecoveryCache()
    }

    /// Saves the buffer to a user-selected file location.
    public func saveAs(to newURL: URL) async throws {
        // Suppress the old watcher's notification of the file deletion (ISS-035).
        fileWatcher?.setSuppressNextChange()

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

    /// Opens the HTML Preview panel with the current file (⌘⌥P, File menu).
    /// Routes via the app's InterPanelRouter; no-op if HTML mode is inactive or no file is open.
    public func renderAsHTML() async throws {
        guard htmlModeActive, let url = fileURL else { return }
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
