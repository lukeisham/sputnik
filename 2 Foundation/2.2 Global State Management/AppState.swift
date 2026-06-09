import Foundation
import Observation

/// The single, thread-safe source of truth for the app's global runtime state.
///
/// Created once in `SputnikApp` and injected into the view hierarchy via
/// `.environment(appState)`. All modules read from it through `@Environment`.
///
/// **Writers:**
/// - `InterPanelRouter` (2.1) is the sole writer for document state (`openDocuments`,
///   `activeDocumentID`) and the recent-files list.
/// - `DocumentTabBar` (2.4) writes `activeDocumentID` on tab-tap (same Foundation layer).
/// - The View menu / toolbar writes `layout` visibility flags directly (same layer).
///
/// **Threading:** `AppState` is `@MainActor` — all reads and writes happen on the main
/// thread. Background file-system events must hop to `@MainActor` before mutating any
/// property; the actor isolation makes this a compile-time guarantee (SW-1, SR-4).
@Observable
@MainActor
public final class AppState {

    // MARK: - Workspace

    /// The folder currently shown in the File Tree and used as the terminal working directory.
    /// `nil` until the user opens a project folder.
    public var activeWorkspaceDirectory: URL?

    // MARK: - Multi-document tab model (resolves ISS-005)

    /// Ordered list of all open document sessions; drives the tab bar.
    ///
    /// Append / remove via `InterPanelRouter.open(_:)` and `close(_:)` only.
    /// The order matches the visual left-to-right tab order.
    public var openDocuments: [DocumentSession] = []

    /// The `id` of the session currently visible in the editor and previews.
    /// `nil` when no documents are open (placeholder state).
    public var activeDocumentID: UUID?

    /// The currently active `DocumentSession`, derived from `activeDocumentID`.
    /// Returns `nil` when no documents are open. All panels that render file content
    /// observe this computed property.
    public var activeDocument: DocumentSession? {
        guard let id = activeDocumentID else { return nil }
        return openDocuments.first { $0.id == id }
    }

    // MARK: - Layout (panel arrangement, visibility, recent files)

    /// The live, observable layout state: slot assignments, per-slot visibility, the
    /// pinned-terminal visibility flag, and the recent-files list.
    ///
    /// Restored from `PersistenceService` at launch and flushed back on quit
    /// (see `AppDelegate`). The View menu mutates the visibility flags directly; the
    /// `InterPanelRouter` mutates `recentFiles` via `noteRecentFile(_:)`.
    public var layout: LayoutState = .default

    /// Recent file URLs, newest first (read-only convenience over `layout.recentFiles`).
    public var recentFiles: [URL] { layout.recentFiles }

    // MARK: - Backward-compatible read accessors
    //
    // These derived properties let any code written against the old single-file model
    // continue to compile. They are read-only; do not add setters — all writes must
    // go through `InterPanelRouter` and the `openDocuments` / `activeDocumentID` path.

    /// The URL of the currently active document. `nil` when nothing is open or the
    /// active document is untitled.
    public var currentlyOpenFile: URL? {
        activeDocument?.url
    }

    /// The `FileType` of the currently active document. `.unknown` when nothing is open.
    public var currentlyOpenFileType: FileType {
        activeDocument?.fileType ?? .unknown
    }

    // MARK: - Help routing (module 9 Resources fills the presentation)

    /// The current help request: which panel to reveal and, optionally, which topic to
    /// navigate to once revealed. `nil` when no help is open.
    ///
    /// This is the single Foundation-owned help route (SR-1). The Help menu sets it with
    /// `topicID == nil`; the editor's "Look Up Help" sets it with a resolved `topicID`.
    /// Module 9 (Resources) observes this to present the matching guide and navigate;
    /// clearing it dismisses the help surface.
    public var requestedHelpTarget: HelpRequest?

    /// Backward-compatible accessor over `requestedHelpTarget` for callers that only deal
    /// in the topic kind (e.g. the Help menu, the right-column panel switch). Reading
    /// returns the requested panel kind; writing reveals that panel at its overview.
    public var requestedHelpTopic: HelpTopic? {
        get { requestedHelpTarget?.kind }
        set { requestedHelpTarget = newValue.map { HelpRequest(kind: $0) } }
    }

    // MARK: - Processing state (F-5)

    /// Tracks re-entrant processing requests. `true` while `processingCount > 0`.
    /// Modules call `beginProcessing()` / `endProcessing()` around async AI work.
    private var processingCount: Int = 0

    /// Whether Sputnik is currently performing AI processing.
    /// The status bar satellite icon spins while this is `true`.
    public var isProcessing: Bool { processingCount > 0 }

    /// Called before an AI operation begins (must pair with `endProcessing`).
    public func beginProcessing() {
        processingCount += 1
    }

    /// Called after an AI operation finishes.
    public func endProcessing() {
        if processingCount > 0 { processingCount -= 1 }
    }

    // MARK: - Context usage (F-5)

    /// The latest AI context-window usage snapshot, if available.
    /// Set by any module making AI calls; displayed in the status bar
    /// when a model is configured and usage is non-nil.
    public var contextUsage: ContextUsage?

    // MARK: - Terminal model detection (F-8)

    /// Information about an AI model detected in the terminal session.
    /// `nil` when no model is active or detected.
    public var terminalModelInfo: TerminalModelInfo?

    // MARK: - Scratchpad (F-6)

    /// Whether the scratchpad overlay panel is currently visible.
    public var scratchpadVisible: Bool = false

    /// The current text content of the scratchpad.
    public var scratchpadText: String = ""

    /// The scratchpad panel's size and position (offset from bottom-right corner).
    /// - `.origin.x`: horizontal offset from the right edge (positive = rightward)
    /// - `.origin.y`: vertical offset from the bottom edge (positive = upward)
    /// - `.size`:    panel dimensions (minimum 200 × 120)
    public var scratchpadFrame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 240)

    // MARK: - Init

    public init() {}

    // MARK: - Recent files

    /// Records `url` as the most-recently-opened file, de-duplicating and capping the list.
    /// Called by `InterPanelRouter.open(_:)`.
    public func noteRecentFile(_ url: URL) {
        var list = layout.recentFiles
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        if list.count > LayoutState.maxRecentFiles {
            list.removeLast(list.count - LayoutState.maxRecentFiles)
        }
        layout.recentFiles = list
    }

    /// Clears the recent-files list (File ▸ Open Recent ▸ Clear Menu).
    public func clearRecentFiles() {
        layout.recentFiles.removeAll()
    }

    // MARK: - Panel visibility (replaces Focus Modes)

    /// Whether the given slot is currently visible. Hidden slots are absent or `false`.
    public func isVisible(_ position: PanelPosition) -> Bool {
        layout.visibility[position] ?? true
    }

    /// Toggles the visibility of a relocatable slot.
    public func toggleVisibility(_ position: PanelPosition) {
        layout.visibility[position] = !isVisible(position)
    }

    /// Toggles the pinned Terminal strip.
    public func toggleTerminal() {
        layout.terminalVisible.toggle()
    }

    /// Restores the default panel arrangement and visibility, preserving open documents
    /// and the recent-files list.
    public func restoreDefaultLayout() {
        layout.panelLayout = .default
        layout.visibility = Dictionary(
            uniqueKeysWithValues: PanelPosition.allCases.map { ($0, true) }
        )
        layout.terminalVisible = true
    }

    // MARK: - Document lifecycle
    //
    // These mutators are the concrete document-state writes. The `InterPanelRouter` (2.1)
    // is the documented routing seam and delegates to these; Foundation-layer UI (the menu
    // bar, `DocumentTabBar`) may also call them directly since it lives in the same layer.
    // Content loading and the dirty-save guard are owned by the Text Editor (module 3) and
    // are wired in where marked, so Foundation never embeds editor file-IO semantics.

    /// Opens `url` using find-or-create semantics: if a session for this URL already
    /// exists it is made active; otherwise a new session is appended and activated.
    /// The file's text is loaded lazily by the editor (module 3) when it mounts.
    @discardableResult
    public func openDocument(url: URL) -> DocumentSession {
        if let existing = openDocuments.first(where: { $0.url == url }) {
            activeDocumentID = existing.id
            noteRecentFile(url)
            return existing
        }
        let session = DocumentSession(url: url, fileType: FileType(url: url))
        openDocuments.append(session)
        activeDocumentID = session.id
        noteRecentFile(url)
        return session
    }

    /// Creates a new untitled, empty document and makes it active (File ▸ New Tab).
    @discardableResult
    public func newUntitledDocument() -> DocumentSession {
        let session = DocumentSession(url: nil, fileType: .text)
        openDocuments.append(session)
        activeDocumentID = session.id
        return session
    }

    /// Closes the session identified by `id`, reselecting the nearest neighbouring tab
    /// (or `nil` when the list becomes empty).
    ///
    /// - Note: the unsaved-changes guard for a dirty session is owned by the close path in
    ///   `InterPanelRouter` / the Text Editor (module 3); this method performs the removal
    ///   once that guard has passed.
    public func closeDocument(_ id: UUID) {
        guard let index = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeDocumentID == id
        openDocuments.remove(at: index)
        guard wasActive else { return }
        if openDocuments.isEmpty {
            activeDocumentID = nil
        } else {
            let neighbour = min(index, openDocuments.count - 1)
            activeDocumentID = openDocuments[neighbour].id
        }
    }
}
