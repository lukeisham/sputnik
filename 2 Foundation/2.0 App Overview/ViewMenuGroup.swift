import AppKit
import SwiftUI

struct ViewMenuGroup: Commands {

    private let appState: AppState
    private let settings: SettingsStore

    init(appState: AppState, settings: SettingsStore) {
        self.appState = appState
        self.settings = settings
    }

    var body: some Commands {
        CommandMenu("View") {
            Button("Toggle File Tree") {
                appState.toggleVisibility(.left)
            }
            .keyboardShortcut("1", modifiers: [.option, .command])

            Button("Toggle Preview") {
                appState.toggleVisibility(.centerLower)
            }
            .keyboardShortcut("2", modifiers: [.option, .command])

            Button("Toggle Right Panel") {
                appState.toggleVisibility(.right)
            }
            .keyboardShortcut("3", modifiers: [.option, .command])

            Button("Toggle Terminal") {
                appState.toggleTerminal()
            }
            .keyboardShortcut("4", modifiers: [.option, .command])

            Divider()

            Toggle(
                "Scratchpad",
                isOn: Binding(
                    get: { appState.scratchpadVisible },
                    set: { appState.scratchpadVisible = $0 }
                )
            )
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Focus: Editor") {
                appState.layout.visibility[.left] = false
                appState.layout.visibility[.right] = false
                appState.layout.visibility[.centerUpper] = true
                appState.layout.visibility[.centerLower] = false
            }
            .keyboardShortcut("e", modifiers: [.control, .command])

            Button("Focus: Reader") {
                appState.layout.visibility[.left] = false
                appState.layout.visibility[.right] = false
                appState.layout.visibility[.centerUpper] = false
                appState.layout.visibility[.centerLower] = true
            }
            .keyboardShortcut("r", modifiers: [.control, .command])

            Button("Restore Default Layout") {
                appState.restoreDefaultLayout()
            }
            .keyboardShortcut("0", modifiers: [.control, .command])

            Divider()

            Menu("Appearance") {
                Button("Light Mode") {
                    settings.setTheme(.light)
                }
                Button("Dark Mode") {
                    settings.setTheme(.dark)
                }
                Button("Use System Setting") {
                    settings.setTheme(.system)
                }
            }
        }
    }
}
