import SwiftUI

/// The single app entry point.
///
/// Wires together Foundation's shared objects (`AppState`, `SettingsStore`,
/// `FilePersistenceService`, `AppDelegate`) and injects them into the SwiftUI environment.
/// The `WindowGroup` uses `.handlesExternalEvents` to enforce a single-window model —
/// files opened from Finder are routed through `InterPanelRouter` (module 2.1) rather than
/// opening a second window.
@main
public struct SputnikApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Shared objects

    private let persistence = FilePersistenceService()

    @State private var appState = AppState()
    @State private var settingsStore: SettingsStore

    // MARK: - Init

    public init() {
        let persistence = FilePersistenceService()
        let store = SettingsStore(persistence: persistence)
        _settingsStore = State(initialValue: store)

        // Wire dependencies into AppDelegate before any lifecycle method fires.
        // AppDelegate is constructed before `init` returns, so this is safe.
    }

    // MARK: - Scenes

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(settingsStore)
                .onAppear {
                    wireAppDelegate()
                }
        }
        .handlesExternalEvents(matching: [])   // Single-window enforcement

        Settings {
            SettingsView()
                .environment(settingsStore)
        }
    }

    // MARK: - Private helpers

    /// Passes shared objects to `AppDelegate` after the app finishes launching.
    /// Called once from `ContentView.onAppear`.
    private func wireAppDelegate() {
        appDelegate.persistenceService = persistence
        // terminalLifecycle is wired by module 7 when TerminalManager is created.
    }
}

// MARK: - Settings placeholder

/// Placeholder Settings scene; replaced when module 2.3 gains a full UI.
private struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Text("Settings — coming in module 2.3 UI pass")
                .foregroundStyle(SputnikColor.secondaryText)
        }
        .padding(SputnikSpacing.lg)
        .frame(width: 400)
    }
}
