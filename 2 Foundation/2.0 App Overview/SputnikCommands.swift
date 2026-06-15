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
    private let focusCoordinator: PanelFocusCoordinator

    public init(
        appState: AppState, settings: SettingsStore, router: AppInterPanelRouter,
        focusCoordinator: PanelFocusCoordinator
    ) {
        self.appState = appState
        self.settings = settings
        self.router = router
        self.focusCoordinator = focusCoordinator
    }

    public var body: some Commands {
        SputnikMenuGroup()
        FileMenuGroup(appState: appState)
        EditMenuGroup(settings: settings, appState: appState)
        TerminalIntegrationCommands(appState: appState)
        FormatMenuGroup(appState: appState)
        ViewMenuGroup(appState: appState, settings: settings, focusCoordinator: focusCoordinator)
        WindowMenuGroup(appState: appState, router: router)
        HelpMenuGroup(appState: appState, settings: settings)
    }
}

// MARK: - Terminal integration commands

private struct TerminalIntegrationCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()

            Button("Send Selection to Terminal") {
                appState.editorCommandHandler?.sendSelectionToTerminal()
            }
            .keyboardShortcut("e", modifiers: [.command, .control])
            .disabled(appState.editorCommandHandler == nil)

            Button("Run Current File in Terminal") {
                appState.editorCommandHandler?.runCurrentFileInTerminal()
            }
            .keyboardShortcut("r", modifiers: [.command, .control])
            .disabled(appState.editorCommandHandler == nil)

            Button("Insert Terminal Selection") {
                appState.editorCommandHandler?.insertTerminalSelection()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(appState.editorCommandHandler == nil)

            Button("Insert Last Command Output") {
                appState.editorCommandHandler?.insertLastCommandOutput()
            }
            .keyboardShortcut("o", modifiers: [.command, .control])
            .disabled(appState.editorCommandHandler == nil)

            Divider()

            Button("New Terminal Tab") {
                appState.activeWindow?.newTerminalTabRequested &+= 1
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(appState.activeWindow == nil)
        }
    }
}
