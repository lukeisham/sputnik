import Foundation
import Observation
import SwiftUI

// MARK: - FocusedValues key for frontmost-window tracking

public struct ActiveWindowIDKey: FocusedValueKey {
    public typealias Value = UUID
}

extension FocusedValues {
    /// Set by each `ContentView.onAppear` → `.focusedSceneValue(\.activeWindowID, windowState.id)`.
    /// `SputnikCommands` or `AppState` can read this to determine the current key window.
    public var activeWindowID: UUID? {
        get { self[ActiveWindowIDKey.self] }
        set { self[ActiveWindowIDKey.self] = newValue }
    }
}

/// Per-window state container.
///
/// One instance exists for every open Sputnik window. `AppState` acts as the
/// coordinator that owns the collection of `WindowState` objects; each window's
/// view hierarchy receives its `WindowState` via the SwiftUI environment
/// (`.environment(windowState)`).
///
/// **Ownership:** Created by `AppState.createWindow()`. The matching `NSWindow`
/// is opened by SwiftUI's `openWindow(id:value:)` action using `id` as the
/// scene value.
///
/// **Threading:** `@MainActor` — all reads and writes happen on the main thread.
// @MainActor isolation makes Sendable conformance redundant — the actor enforces
// single-threaded access on the main actor.
@Observable
@MainActor
public final class WindowState {

    // MARK: - Identity

    /// Stable UUID used as the SwiftUI scene value to identify this window.
    public let id: UUID

    /// The display title for the window — the workspace folder name, or "Untitled".
    public var title: String {
        activeWorkspaceDirectory?.lastPathComponent ?? "Untitled"
    }

    // MARK: - Workspace

    /// The folder currently shown in this window's File Tree and used as its
    /// terminal working directory. `nil` until the user opens a project folder.
    public var activeWorkspaceDirectory: URL?

    // MARK: - Multi-document tab model

    /// Ordered list of open document sessions in this window.
    public var openDocuments: [DocumentSession] = []

    /// The `id` of the session currently visible in this window's editor.
    public var activeDocumentID: UUID?

    /// The currently active `DocumentSession` for this window.
    public var activeDocument: DocumentSession? {
        guard let id = activeDocumentID else { return nil }
        return openDocuments.first { $0.id == id }
    }

    // MARK: - Backward-compatible read accessors

    public var currentlyOpenFile: URL? { activeDocument?.url }
    public var currentlyOpenFileType: FileType { activeDocument?.fileType ?? .unknown }

    // MARK: - Layout

    /// Per-window panel arrangement, slot visibility, and terminal pinned flag.
    public var layout: LayoutState = .default

    // MARK: - Help routing

    /// The current help request for this window. `nil` when no help panel is open.
    public var requestedHelpTarget: HelpRequest?

    public var requestedHelpTopic: HelpTopic? {
        get { requestedHelpTarget?.kind }
        set { requestedHelpTarget = newValue.map { HelpRequest(kind: $0) } }
    }

    // MARK: - Processing state (per-window AI)

    private var processingCount: Int = 0

    /// Whether this window is currently performing AI work.
    public var isProcessing: Bool { processingCount > 0 }

    public func beginProcessing() { processingCount += 1 }
    public func endProcessing() { if processingCount > 0 { processingCount -= 1 } }

    // MARK: - AI state

    /// Main AI state detected in this window's terminal session.
    public var mainAIState: MainAIState?

    // MARK: - Scratchpad (per-window F-6)

    public var scratchpadVisible: Bool = false
    public var scratchpadText: String = ""
    public var scratchpadFrame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 240)

    // MARK: - Terminal manager reference

    /// The terminal manager owned by this window. Stored here so it survives
    /// view redraws and is accessible from `AppDelegate` for clean shutdown.
    ///
    /// Set by `TerminalView` via `.onAppear`; `weak` is not used because
    /// `WindowState` should outlive the view.
    public var terminalManager: (any TerminalLifecycle)?

    // MARK: - Init

    public init(id: UUID = UUID()) {
        self.id = id
    }

    // MARK: - Document lifecycle

    @discardableResult
    public func openDocument(url: URL) -> DocumentSession {
        if let existing = openDocuments.first(where: { $0.url == url }) {
            activeDocumentID = existing.id
            return existing
        }
        let session = DocumentSession(url: url, fileType: FileType(url: url))
        openDocuments.append(session)
        activeDocumentID = session.id
        return session
    }

    @discardableResult
    public func newUntitledDocument() -> DocumentSession {
        let session = DocumentSession(url: nil, fileType: .text)
        openDocuments.append(session)
        activeDocumentID = session.id
        return session
    }

    /// Reorders documents using the same index semantics as `ForEach.onMove` / `List.onMove`.
    /// `activeDocumentID` is unchanged — the active tab stays active regardless of its new position.
    public func moveDocument(fromOffsets: IndexSet, toOffset: Int) {
        openDocuments.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

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

    // MARK: - Panel visibility

    public func isVisible(_ position: PanelPosition) -> Bool {
        layout.visibility[position] ?? true
    }

    public func toggleVisibility(_ position: PanelPosition) {
        layout.visibility[position] = !isVisible(position)
    }

    public func toggleTerminal() {
        layout.terminalVisible.toggle()
    }

    public func restoreDefaultLayout() {
        layout.panelLayout = .default
        layout.visibility = Dictionary(
            uniqueKeysWithValues: PanelPosition.allCases.map { ($0, true) }
        )
        layout.terminalVisible = true
    }
}
