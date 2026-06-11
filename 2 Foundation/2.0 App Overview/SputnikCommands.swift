import AppKit
import SwiftUI

/// Wires all macOS menu bar menus to `AppState` and `SettingsStore` actions.
///
/// Attach to `WindowGroup` via `.commands { SputnikCommands(appState:settings:) }` in `SputnikApp`.
/// Dependencies are passed directly because `Commands` bodies run outside the SwiftUI view
/// hierarchy and cannot reliably read `@Environment` values injected on a `WindowGroup`.
public struct SputnikCommands: Commands {

    private let appState: AppState
    private let settings: SettingsStore
    private let router: AppInterPanelRouter

    public init(appState: AppState, settings: SettingsStore, router: AppInterPanelRouter) {
        self.appState = appState
        self.settings = settings
        self.router = router
    }

    public var body: some Commands {
        SputnikMenuGroup()
        FileMenuGroup(appState: appState)
        EditMenuGroup(settings: settings)
        FormatMenuGroup(appState: appState)
        ViewMenuGroup(appState: appState, settings: settings)
        WindowMenuGroup(appState: appState, router: router)
        HelpMenuGroup(appState: appState)
    }
}
