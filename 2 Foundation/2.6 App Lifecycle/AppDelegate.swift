import AppKit

/// Handles app-level lifecycle events that SwiftUI's `App` protocol cannot express.
///
/// Registered in `SputnikApp` via `@NSApplicationDelegateAdaptor`. Responsibilities:
/// 1. **Launch** — restore layout, surface crash-recovery dialogs, start `SputnikMenuBarController`
///    and `ProcessMonitor`.
/// 2. **Termination gate** — request a clean PTY shutdown via `TerminalLifecycle`, returning
///    `.terminateLater` until the PTYs confirm they are dead.
/// 3. **Flush** — write layout state to disk in `applicationWillTerminate`.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Dependencies (set by SputnikApp after construction)

    /// The concrete persistence service; set before `applicationDidFinishLaunching` fires.
    public var persistenceService: (any PersistenceService)?

    /// The terminal lifecycle handler; set by module 7 during its own startup.
    /// `weak` because module 7 owns the concrete object.
    public weak var terminalLifecycle: (any TerminalLifecycle)?

    /// The shared app state; wired by `SputnikApp` before launch completes.
    public var appState: AppState?

    /// The current layout state; refreshed from `persistenceService.restore()` at launch.
    public var layoutState: LayoutState = .default

    /// A weak reference to the main window; obtained once after launch. Used by the
    /// Foundation UI layer for layout restoration and toolbar config.
    public weak var mainWindow: NSWindow?

    // MARK: - Long-lived Foundation objects (F-1, F-5)

    /// Owns the `NSStatusItem` for the app's lifetime (F-1). Strong — never deallocated.
    private var menuBarController: SputnikMenuBarController?

    /// Polls RAM and CPU for the status bar (F-5). Strong — started at launch, stopped on quit.
    public var processMonitor: ProcessMonitor?

    // MARK: - NSApplicationDelegate

    public func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindow = NSApp.windows.first

        // F-1: Install the menu-bar satellite icon as soon as we have an AppState.
        if let state = appState {
            menuBarController = SputnikMenuBarController(appState: state)
        }

        // F-5: Start polling RAM/CPU for the status bar.
        processMonitor?.start()

        guard let persistence = persistenceService else { return }

        Task {
            layoutState = await persistence.restore()

            // Restore scratchpad state (F-6)
            if let state = appState {
                state.scratchpadText = persistence.loadScratchpadText()
                state.scratchpadFrame = persistence.loadScratchpadFrame()
            }

            let pendingNames = persistence.pendingRecoveryNames()
            for name in pendingNames {
                let alert = SputnikAlert.recoveryAvailable(filename: name)
                presentAlert(alert)
            }
        }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    {
        guard let terminal = terminalLifecycle else { return .terminateNow }

        Task {
            await terminal.killAllPTYs()
            NSApp.replyToApplicationShouldTerminate(true)
        }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // F-5: stop the process-monitor polling loop before the process exits.
        processMonitor?.stop()
        persistenceService?.flushLayout(layoutState)

        // Save scratchpad state (F-6)
        if let state = appState {
            persistenceService?.saveScratchpad(text: state.scratchpadText)
            persistenceService?.saveScratchpad(frame: state.scratchpadFrame)
        }
    }

    // MARK: - Private helpers

    private func presentAlert(_ alert: SputnikAlert) {
        let panel = NSAlert()
        panel.messageText = alert.title
        panel.informativeText = alert.message
        panel.alertStyle = .warning
        panel.addButton(withTitle: "OK")
        panel.runModal()
    }
}
