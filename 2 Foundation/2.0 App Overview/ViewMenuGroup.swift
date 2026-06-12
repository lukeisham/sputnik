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
                appState.toggleColumn(renderMode: .fileTree)
            }
            .keyboardShortcut("1", modifiers: [.option, .command])

            Button("Toggle Preview") {
                appState.toggleColumn(renderMode: .markdownPreview)
            }
            .keyboardShortcut("2", modifiers: [.option, .command])

            Button("Toggle Right Panel") {
                appState.toggleColumn(renderMode: .htmlPreview)
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
                appState.focusEditor()
            }
            .keyboardShortcut("e", modifiers: [.control, .command])

            Button("Focus: Reader") {
                appState.focusReader()
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
