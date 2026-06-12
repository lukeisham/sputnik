import Foundation
import Observation

/// Coordinator for all open windows. Owns the collection of `WindowState` instances
/// and provides computed pass-through accessors that delegate to the active window,
/// so existing callers written against the single-window model continue to compile.
///
/// **Multi-window model:**
/// - One `WindowState` per open window. Created via `createWindow()`.
/// - `activeWindowID` tracks the frontmost window, updated via `setActiveWindow(_:)`.
/// - All "current document / layout" reads delegate to `activeWindow`.
///
/// **Threading:** `@MainActor` — all reads and writes happen on the main thread.
///
/// **Sendable:** This class does not conform to `Sendable`. It is `@MainActor`-isolated,
/// so all property access is confined to the main actor. Callers that need to read
/// `AppState` from outside the main actor must use `Task { @MainActor in … }` or
/// explicitly isolate themselves. Do **not** add `@unchecked Sendable` — it would
/// suppress data-race detection without providing any safety benefit.
@Observable
@MainActor
public final class AppState {

    // MARK: - Window registry

    /// Ordered list of window IDs (insertion order = creation order).
    public private(set) var orderedWindowIDs: [UUID] = []

    /// All open windows, keyed by their stable UUID.
    public private(set) var windows: [UUID: WindowState] = [:]

    /// The UUID of the currently frontmost window. Updated by `setActiveWindow(_:)`
    /// when the key window changes (via `@FocusedValue` or `NSApp.keyWindow` observation).
    public var activeWindowID: UUID?

    /// The frontmost window's state. `nil` only if no windows exist yet.
    public var activeWindow: WindowState? {
        guard let id = activeWindowID else { return orderedWindowIDs.first.flatMap { windows[$0] } }
        return windows[id]
    }

    // MARK: - Window lifecycle

    /// Creates a new `WindowState`, registers it, and makes it the active window.
    @discardableResult
    public func createWindow() -> WindowState {
        let w = WindowState()
        windows[w.id] = w
        orderedWindowIDs.append(w.id)
        activeWindowID = w.id
        return w
    }

    /// Removes a window from the registry and selects a new active window if needed.
    /// Callers must have already killed the window's terminal and confirmed any dirty tabs.
    public func closeWindow(_ id: UUID) {
        windows.removeValue(forKey: id)
        orderedWindowIDs.removeAll { $0 == id }
        if activeWindowID == id {
            activeWindowID = orderedWindowIDs.last
        }
    }

    /// Returns the `WindowState` for `id`, or `nil` if it no longer exists.
    public func windowForID(_ id: UUID) -> WindowState? {
        windows[id]
    }

    /// Called by the frontmost-window tracker (via `@FocusedValue`) when the key
    /// window changes.
    public func setActiveWindow(_ id: UUID) {
        guard windows[id] != nil else { return }
        activeWindowID = id
    }

    // MARK: - Computed pass-throughs to active window
    //
    // These let all existing callers written against the single-window model
    // continue to compile unchanged. Reads delegate to `activeWindow`; writes
    // also delegate so that menu commands and `SputnikCommands` work naturally.

    public var activeWorkspaceDirectory: URL? {
        get { activeWindow?.activeWorkspaceDirectory }
        set { activeWindow?.activeWorkspaceDirectory = newValue }
    }

    public var openDocuments: [DocumentSession] {
        get { activeWindow?.openDocuments ?? [] }
        set { activeWindow?.openDocuments = newValue }
    }

    public var activeDocumentID: UUID? {
        get { activeWindow?.activeDocumentID }
        set { activeWindow?.activeDocumentID = newValue }
    }

    public var activeDocument: DocumentSession? {
        activeWindow?.activeDocument
    }

    public var currentlyOpenFile: URL? { activeDocument?.url }
    public var currentlyOpenFileType: FileType { activeDocument?.fileType ?? .unknown }

    public var layout: LayoutState {
        get { activeWindow?.layout ?? .default }
        set { activeWindow?.layout = newValue }
    }

    public var recentFiles: [URL] { layout.recentFiles }

    public var requestedHelpTarget: HelpRequest? {
        get { activeWindow?.requestedHelpTarget }
        set { activeWindow?.requestedHelpTarget = newValue }
    }

    public var requestedHelpTopic: HelpTopic? {
        get { activeWindow?.requestedHelpTopic }
        set { activeWindow?.requestedHelpTopic = newValue }
    }

    /// `true` if *any* open window is currently processing AI work.
    /// Used by `SputnikMenuBarController` (the menu-bar icon is global).
    public var isProcessing: Bool {
        windows.values.contains { $0.isProcessing }
    }

    public func beginProcessing() { activeWindow?.beginProcessing() }
    public func endProcessing() { activeWindow?.endProcessing() }

    // MARK: - AI state (global — Supporting AI is app-level; Main AI is per-window)

    /// Cumulative Supporting AI token usage for the current session.
    public var supportingAIUsage: SupportingAIUsage?

    /// Delegates to the active window for Main AI state.
    public var mainAIState: MainAIState? {
        get { activeWindow?.mainAIState }
        set { activeWindow?.mainAIState = newValue }
    }

    // MARK: - Scratchpad (delegates to active window)

    public var scratchpadVisible: Bool {
        get { activeWindow?.scratchpadVisible ?? false }
        set { activeWindow?.scratchpadVisible = newValue }
    }

    public var scratchpadText: String {
        get { activeWindow?.scratchpadText ?? "" }
        set { activeWindow?.scratchpadText = newValue }
    }

    public var scratchpadDockedWidth: CGFloat {
        get { activeWindow?.scratchpadDockedWidth ?? 280 }
        set { activeWindow?.scratchpadDockedWidth = newValue }
    }

    // MARK: - Document lookup

    public func document(for id: UUID) -> DocumentSession? {
        activeWindow?.document(for: id)
    }

    // MARK: - Terminal registry for clean shutdown

    // MARK: - Editor command handler (SR-1)

    /// The registered editor command handler (Save, Save As, Render as HTML, ASCII Studio).
    /// Set by the text editor module at launch via `registerEditorCommandHandler(_:)`.
    public private(set) var editorCommandHandler: EditorCommandHandling?

    /// The inter-panel router used by the editor to open files in other panels.
    /// Set by the app at launch; required for Render as HTML and other routing operations.
    public weak var router: (any InterPanelRouter)?

    /// Registers the editor command handler (called by EditorViewModel at init).
    public func registerEditorCommandHandler(_ handler: EditorCommandHandling) {
        editorCommandHandler = handler
    }

    // MARK: - Multi-window persistence (step 9)

    /// Window IDs that still need their SwiftUI scene opened after launch.
    /// Populated during `restoreWindows(from:)` for all windows beyond the first,
    /// which is already handled by the initial `WindowGroup` scene creation.
    public var pendingWindowIDs: [UUID] = []

    /// Replaces all current windows with restored descriptors from persistence.
    /// The first descriptor's window is already shown by the initial `WindowGroup`;
    /// additional descriptors are collected in `pendingWindowIDs` for the scene
    /// to open via `openWindow(id:value:)`.
    ///
    /// If `descriptors` is empty, the auto-created initial window from `init()`
    /// is left intact.
    public func restoreWindows(from descriptors: [WindowDescriptor]) {
        guard !descriptors.isEmpty else { return }

        // Remove all existing windows (including the auto-created first one).
        windows.removeAll()
        orderedWindowIDs.removeAll()
        pendingWindowIDs.removeAll()

        for desc in descriptors {
            let ws = WindowState(id: desc.id)
            ws.activeWorkspaceDirectory = desc.workspaceDirectoryURL
            ws.layout = desc.layout

            // Re-open persisted tabs (non-untitled).
            for url in desc.openTabURLs {
                ws.openDocument(url: url)
            }
            // Restore which tab was active (match by URL).
            if let activeURL = desc.activeDocumentURL {
                ws.activeDocumentID = ws.openDocuments.first { $0.url == activeURL }?.id
            }

            windows[ws.id] = ws
            orderedWindowIDs.append(ws.id)
        }

        activeWindowID = orderedWindowIDs.first

        // Windows beyond the first need their SwiftUI scene opened.
        if orderedWindowIDs.count > 1 {
            pendingWindowIDs = Array(orderedWindowIDs.dropFirst())
        }
    }

    /// Collects the current state of every open window into an array of
    /// `WindowDescriptor` values, ready for `saveWindows(_:)`.
    public func collectDescriptors() -> [WindowDescriptor] {
        orderedWindowIDs.compactMap { id in
            guard let ws = windows[id] else { return nil }
            return WindowDescriptor(
                id: ws.id,
                workspaceDirectoryURL: ws.activeWorkspaceDirectory,
                openTabURLs: ws.openDocuments.compactMap { $0.url },
                activeDocumentURL: ws.activeDocument?.url,
                layout: ws.layout
            )
        }
    }

    /// All `TerminalLifecycle` instances across every open window.
    /// `AppDelegate.applicationShouldTerminate` iterates these to kill every PTY.
    public var allTerminalManagers: [any TerminalLifecycle] {
        windows.values.compactMap { $0.terminalManager }
    }

    // MARK: - Init

    public init() {
        // Create the first window immediately so the app has a valid active window
        // before the first `ContentView` renders.
        let first = WindowState()
        windows[first.id] = first
        orderedWindowIDs.append(first.id)
        activeWindowID = first.id
    }

    // MARK: - Recent files

    public func noteRecentFile(_ url: URL) {
        var list = layout.recentFiles
        list.removeAll { $0 == url }
        list.insert(url, at: 0)
        if list.count > LayoutState.maxRecentFiles {
            list.removeLast(list.count - LayoutState.maxRecentFiles)
        }
        layout.recentFiles = list
    }

    public func clearRecentFiles() {
        layout.recentFiles.removeAll()
    }

    // MARK: - Panel visibility (dynamic layout)

    /// Returns true if a column with the given render mode exists in the active window.
    public func hasColumn(renderMode: PanelID) -> Bool {
        activeWindow?.hasColumn(renderMode: renderMode) ?? false
    }

    /// Toggle a column by render mode: remove if present, add if absent.
    public func toggleColumn(renderMode: PanelID) {
        activeWindow?.toggleColumn(renderMode: renderMode)
    }

    public func toggleTerminal() {
        activeWindow?.toggleTerminal()
    }

    public func restoreDefaultLayout() {
        activeWindow?.restoreDefaultLayout()
    }

    /// Reconfigure the active window to a focused editor layout (text editor only).
    public func focusEditor() {
        activeWindow?.setDynamicLayout(
            DynamicPanelLayout(columns: [
                PanelColumn(renderMode: .fileTree, width: 0.20),
                PanelColumn(renderMode: .textEditor, width: 0.80),
            ]))
    }

    /// Reconfigure the active window to a focused reader layout (markdown preview only, no file tree).
    public func focusReader() {
        activeWindow?.setDynamicLayout(
            DynamicPanelLayout(columns: [
                PanelColumn(renderMode: .markdownPreview, width: 1.0)
            ]))
    }

    // MARK: - Document lifecycle (delegates to active window + updates recent files)

    @discardableResult
    public func openDocument(url: URL) -> DocumentSession {
        guard let win = activeWindow else {
            let w = createWindow()
            return w.openDocument(url: url)
        }
        let session = win.openDocument(url: url)
        noteRecentFile(url)
        return session
    }

    @discardableResult
    public func newUntitledDocument() -> DocumentSession {
        guard let win = activeWindow else {
            let w = createWindow()
            return w.newUntitledDocument()
        }
        return win.newUntitledDocument()
    }

    public func closeDocument(_ id: UUID) {
        activeWindow?.closeDocument(id)
    }

    /// Reorders documents in the active window. Delegates to `WindowState.moveDocument(fromOffsets:toOffset:)`.
    public func moveDocument(fromOffsets: IndexSet, toOffset: Int) {
        activeWindow?.moveDocument(fromOffsets: fromOffsets, toOffset: toOffset)
    }
}
