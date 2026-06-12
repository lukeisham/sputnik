import AppKit
import SwiftUI

struct ViewMenuGroup: Commands {

    private let appState: AppState
    private let settings: SettingsStore
    private let focusCoordinator: PanelFocusCoordinator

    init(appState: AppState, settings: SettingsStore, focusCoordinator: PanelFocusCoordinator) {
        self.appState = appState
        self.settings = settings
        self.focusCoordinator = focusCoordinator
    }

    var body: some Commands {
        CommandMenu("View") {
            Button("Toggle File Tree") {
                appState.toggleColumn(renderMode: .fileTree)
            }
            .keyboardShortcut("1", modifiers: [.option, .command])

            Button("Toggle Markdown Preview") {
                appState.toggleColumn(renderMode: .markdownPreview)
            }
            .keyboardShortcut("2", modifiers: [.option, .command])

            Button("Toggle HTML Preview") {
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

            Divider()

            Button("Focus: Editor") {
                appState.focusEditor()
            }
            .keyboardShortcut("e", modifiers: [.control, .command])

            Button("Focus: Reader") {
                appState.focusReader()
            }
            .keyboardShortcut("r", modifiers: [.control, .command])

            Divider()

            Section("Focus Navigation") {
                Button("Focus Next Panel") {
                    if let ws = appState.activeWindow {
                        focusCoordinator.focusNext(
                            from: ws.layout.dynamicLayout,
                            terminalVisible: ws.layout.terminalVisible
                        )
                    }
                }
                .keyboardShortcut(.tab, modifiers: [.control])

                Button("Focus Previous Panel") {
                    if let ws = appState.activeWindow {
                        focusCoordinator.focusPrevious(
                            from: ws.layout.dynamicLayout,
                            terminalVisible: ws.layout.terminalVisible
                        )
                    }
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Button("Focus: Editor Panel") {
                    if let ws = appState.activeWindow {
                        focusCoordinator.focusEditor(from: ws.layout.dynamicLayout)
                    }
                }

                Button("Focus: Terminal") {
                    focusCoordinator.focusTerminal()
                }
                .keyboardShortcut("t", modifiers: [.control, .command])

                Button("Focus: File Tree Panel") {
                    if let ws = appState.activeWindow {
                        focusCoordinator.focusFileTree(from: ws.layout.dynamicLayout)
                    }
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }

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
