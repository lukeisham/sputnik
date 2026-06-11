import AppKit
import Foundation
import FoundationModule
import Observation

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
    private var fileWatcher: FileWatcher?

    // MARK: - Crash recovery

    /// Serializes editor buffer to recovery cache on text changes (ISS-036).
    private var recoveryStore: CrashRecoveryStore? = {
        if let appDelegate = NSApp.delegate as? AppDelegate,
            let persistence = appDelegate.persistenceService
        {
            return CrashRecoveryStore(persistence: persistence)
        }
        return nil
    }()

    /// Task for debouncing recovery writes (cancelled when a new write is scheduled).
    private var recoveryDebounceTask: Task<Void, Never>?

    // MARK: - Init

    public init() {
        // Register as the editor command handler (Save, Save As, etc.).
        if let appDelegate = NSApp.delegate as? AppDelegate,
            let appState = appDelegate.appState
        {
            appState.registerEditorCommandHandler(self)
        }
    }

    // MARK: - Deinit

    deinit {
        // Clean up resources on app teardown or view model deallocation (Step 12).
        MainActor.assumeIsolated {
            stopWatchingFile()
            stopRecoveryWrite()
        }
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

        // Validate file size and encoding on background task.
        let encoding = try await Task(priority: .userInitiated) { () -> String.Encoding in
            try EncodingGuard.validate(url)
        }.value

        // Read file content with the detected encoding.
        let text = try String(contentsOf: url, encoding: encoding)

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

        // Start watching the file for external changes (ISS-033).
        startWatchingFile(url: url)
    }

    // MARK: - Helpers

    /// Resets all per-file state when a new file is opened.
    ///
    /// Mode is inferred by the caller from the file extension; reset to `.plainText`
    /// as a safe default so no sub-module is left active from the previous session.
    private func resetForNewFile(url: URL?) {
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
    private func stopWatchingFile() {
        fileWatcher = nil  // Deinit removes the presenter from the coordinator.
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
            await self?.recoveryStore?.scheduleWrite(for: fileURL, content: text)
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

        // Suppress the watcher's notification of our own write (ISS-035).
        fileWatcher?.setSuppressNextChange()

        // Atomic write on background task to keep UI thread clear (SR-4).
        try await Task(priority: .userInitiated) { [weak self] () -> Void in
            guard let self else { return }
            // Write atomically: write to temp file, then swap.
            let tempURL = fileURL.appendingPathExtension("tmp")
            try self.loadedText.write(to: tempURL, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }.value

        // Return to main thread for state updates.
        await MainActor.run {
            isDirty = false
            clearRecoveryCache()
        }
    }

    /// Saves the buffer to a user-selected file location.
    public func saveAs(to newURL: URL) async throws {
        // Suppress the old watcher's notification of the file deletion (ISS-035).
        fileWatcher?.setSuppressNextChange()

        // Atomic write on background task (SR-4).
        try await Task(priority: .userInitiated) { [weak self] () -> Void in
            guard let self else { return }
            try self.loadedText.write(to: newURL, atomically: true, encoding: .utf8)
        }.value

        // Update the editor state to the new file.
        await MainActor.run {
            isDirty = false
            stopWatchingFile()
            fileURL = newURL
            clearRecoveryCache()
            startWatchingFile(url: newURL)
        }
    }

    // MARK: - EditorCommandHandling protocol (steps 10–11)

    /// Opens the HTML Preview panel with the current file (⌘⌥P, File menu).
    /// Routes via the app's InterPanelRouter; no-op if HTML mode is inactive or no file is open.
    public func renderAsHTML() async throws {
        guard htmlModeActive, let url = fileURL else { return }
        if let appDelegate = NSApp.delegate as? AppDelegate,
            let router = appDelegate.appState?.router
        {
            await router.open(url)
        }
    }

    /// Presents the ASCII Studio floating panel (⌘⌥A, Format menu).
    /// Opens for the active text view; no-op if no editor is active.
    public func showASCIIStudio() async throws {
        guard let textView else { return }
        ASCIIStudioPanel.shared.open(for: textView)
    }
}
