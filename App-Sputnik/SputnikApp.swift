import AppKit
import FoundationModule
import SwiftUI

/// The single app entry point.
///
/// Wires together Foundation's shared objects (`AppState`, `SettingsStore`,
/// `FilePersistenceService`, `AppDelegate`) and injects them into the SwiftUI environment.
/// Uses a data-driven `WindowGroup(id:for:UUID.self)` so each new window receives its own
/// `WindowState` (keyed by UUID) and has fully independent document/terminal/layout state.
@main
public struct SputnikApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Shared objects

    private let persistence = FilePersistenceService()

    @State private var appState: AppState
    @State private var settingsStore: SettingsStore
    @State private var processMonitor = ProcessMonitor()  // F-5
    @State private var router = AppInterPanelRouter()
    @State private var supportingAIMonitor: SupportingAIMonitor
    @State private var mainAIMonitor: MainAIMonitor

    // MARK: - Init

    public init() {
        let persistence = FilePersistenceService()
        let state = AppState()
        let store = SettingsStore(persistence: persistence)
        _appState = State(initialValue: state)
        _settingsStore = State(initialValue: store)
        _supportingAIMonitor = State(
            initialValue: SupportingAIMonitor(settingsStore: store, appState: state))
        _mainAIMonitor = State(initialValue: MainAIMonitor(appState: state))
    }

    // MARK: - Scenes

    public var body: some Scene {
        // Data-driven multi-window group. Each window is identified by the UUID of its
        // `WindowState`. SwiftUI creates a new scene instance for each unique value.
        WindowGroup(id: "main", for: UUID.self) { $windowID in
            let windowState: WindowState = {
                // Resolve to the matching WindowState, or fall back to the active window.
                if let id = windowID, let ws = appState.windowForID(id) { return ws }
                if let ws = appState.activeWindow { return ws }
                return appState.createWindow()
            }()
            ContentView(
                windowState: windowState, router: router, appState: appState,
                persistenceService: persistence
            )
            .environment(appState)
            .environment(windowState)
            .environment(settingsStore)
            .environment(processMonitor)  // F-5
            .environment(supportingAIMonitor)
            .environment(mainAIMonitor)
            .onAppear {
                wireAppDelegate()
                // Ensure activeWindowID reflects which window just appeared.
                appState.setActiveWindow(windowState.id)
                // Tag the NSWindow with the WindowState UUID so Merge All Windows
                // can close it by identity (ISS-018).
                NSApp.keyWindow?.identifier = NSUserInterfaceItemIdentifier(
                    windowState.id.uuidString)
            }
            .focusedSceneValue(\.activeWindowID, windowState.id)
            // Opens additional restored windows (step 9) on first render.
            .background {
                WindowRestorerView(appState: appState)
            }
        }
        .commands { SputnikCommands(appState: appState, settings: settingsStore, router: router) }
        // No .handlesExternalEvents(matching: []) — multi-window is intentional.

        // F-2: About window — fixed size, single instance, no toolbar.
        Window("About Sputnik", id: "about") {
            AboutWindowView()
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])  // Second activation raises existing window.

        Settings {
            SettingsView()
                .environment(settingsStore)
                .environment(supportingAIMonitor)
        }
    }

    // MARK: - Private helpers

    /// Passes shared objects to `AppDelegate` once on first window appearance.
    /// Called from each `ContentView.onAppear` but guarded so wiring is idempotent.
    private func wireAppDelegate() {
        guard appDelegate.persistenceService == nil else { return }
        appDelegate.persistenceService = persistence
        appDelegate.appState = appState  // F-1: needed for SputnikMenuBarController
        appDelegate.processMonitor = processMonitor  // F-5: start/stop polling lifecycle
        router.configure(appState: appState)
        appState.router = router  // Make router available to editor for Render as HTML
    }
}
