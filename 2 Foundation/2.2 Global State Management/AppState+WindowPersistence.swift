import AppKit
import Foundation

extension AppState {

    // MARK: - Multi-window persistence (step 9)

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

            // Restore per-document view state (caret + scroll).
            ws.documentViewStates = desc.documentViewStates

            // Restore window frame so it can be applied on window appear.
            ws.restoredWindowFrame = desc.windowFrame

            windows[ws.id] = ws
            orderedWindowIDs.append(ws.id)
        }

        activeWindowID = orderedWindowIDs.first

        // Windows beyond the first need their SwiftUI scene opened.
        if orderedWindowIDs.count > 1 {
            pendingWindowIDs = Array(orderedWindowIDs.dropFirst())
        }
    }

    /// Flushes the active editor's caret/scroll state into the active window's
    /// `documentViewStates` before the descriptors are collected.
    ///
    /// Called from `AppDelegate.applicationWillTerminate` before `collectDescriptors()`.
    /// Only the active (frontmost) window's editor state is captured here because
    /// the `editorCommandHandler` reference points to the last-registered editor
    /// (the one from the most recently created or activated `ContentView`).
    /// Other windows retain whatever state was last set (default if never flushed).
    public func flushViewStates() {
        guard let handler = editorCommandHandler,
            let active = activeWindow
        else { return }
        handler.flushViewState(to: active)
    }

    /// Collects the current state of every open window into an array of
    /// `WindowDescriptor` values, ready for `saveWindows(_:)`.
    /// The caller should call `flushViewStates()` first to ensure the editor's
    /// caret/scroll state is captured into `WindowState.documentViewStates`.
    public func collectDescriptors() -> [WindowDescriptor] {
        orderedWindowIDs.compactMap { id in
            guard let ws = windows[id] else { return nil }
            let frame: CGRect? = {
                guard
                    let nsWindow = NSApp.windows.first(where: {
                        $0.identifier?.rawValue == id.uuidString
                    })
                else { return nil }
                return nsWindow.frame
            }()
            return WindowDescriptor(
                id: ws.id,
                workspaceDirectoryURL: ws.activeWorkspaceDirectory,
                openTabURLs: ws.openDocuments.compactMap { $0.url },
                activeDocumentURL: ws.activeDocument?.url,
                layout: ws.layout,
                windowFrame: frame,
                documentViewStates: ws.documentViewStates
            )
        }
    }

    /// All `TerminalLifecycle` instances across every open window.
    /// `AppDelegate.applicationShouldTerminate` iterates these to kill every PTY.
    public var allTerminalManagers: [any TerminalLifecycle] {
        windows.values.flatMap { $0.terminalManagers }
    }
}
