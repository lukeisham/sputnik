import SwiftUI
import AppKit

/// Wires all six macOS menu bar menus to `AppState` and `SettingsStore` actions.
///
/// Attach to `WindowGroup` via `.commands { SputnikCommands(appState:settings:) }` in `SputnikApp`.
/// Dependencies are passed directly because `Commands` bodies run outside the SwiftUI view
/// hierarchy and cannot reliably read `@Environment` values injected on a `WindowGroup`.
public struct SputnikCommands: Commands {

    private let appState: AppState
    private let settings: SettingsStore

    public init(appState: AppState, settings: SettingsStore) {
        self.appState = appState
        self.settings = settings
    }

    public var body: some Commands {
        sputnikMenu
        fileMenu
        editMenu
        viewMenu
        windowMenu
        helpMenu
    }

    // MARK: - Sputnik menu

    private var sputnikMenu: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sputnik") {
                NSApp.orderFrontStandardAboutPanel(nil)
            }

            Divider()

            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Hide Sputnik") {
                NSApp.hide(nil)
            }
            .keyboardShortcut("h", modifiers: .command)

            Button("Hide Others") {
                NSApp.hideOtherApplications(nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Button("Show All") {
                NSApp.unhideAllApplications(nil)
            }

            Divider()

            Button("Quit Sputnik") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - File menu

    private var fileMenu: some Commands {
        Group {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    appState.newUntitledDocument()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}

            CommandMenu("File") {
                Button("New Window") {
                    // Stub: multi-window is a future feature
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(true)

                Divider()

                Button("Open…") {
                    openDocument()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    if appState.recentFiles.isEmpty {
                        Text("No Recent Files")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                appState.openDocument(url: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            appState.clearRecentFiles()
                        }
                    }
                }

                Divider()

                Button("Close Tab") {
                    if let id = appState.activeDocumentID {
                        appState.closeDocument(id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Close Window") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Divider()

                Button("Save") {
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    // Stub: save pipeline is owned by module 3
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(true)

                Divider()

                Button("Print…") {
                    NSApp.sendAction(#selector(NSDocument.printDocument(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }

    // MARK: - Edit menu

    private var editMenu: some Commands {
        Group {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .textEditing) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Divider()

                Menu("Find") {
                    Button("Find…") {
                        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Button("Find and Replace…") {
                        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])

                    Button("Find Next") {
                        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("g", modifiers: .command)

                    Button("Find Previous") {
                        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                }

                Menu("Spelling and Grammar") {
                    Button("Check Now") {
                        NSApp.sendAction(#selector(NSTextView.checkSpelling(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut(";", modifiers: .command)

                    Toggle(
                        "Check While Typing",
                        isOn: Binding(
                            get: { settings.spellCheckEnabled },
                            set: { settings.setSpellCheckEnabled($0) }
                        )
                    )

                    Toggle(
                        "Grammar Checking",
                        isOn: Binding(
                            get: { settings.grammarCheckEnabled },
                            set: { settings.setGrammarCheckEnabled($0) }
                        )
                    )
                }

                writingAssistanceMenu
            }
        }
    }

    // MARK: - Writing Assistance menu

    private var writingAssistanceMenu: some View {
        Menu("Writing Assistance") {
            // Convenience presets
            Button("All On") {
                settings.setWritingAssistMatrix(.allOn())
            }
            Button("All Off") {
                settings.setWritingAssistMatrix(.allOff())
            }

            Divider()

            // Spelling
            Menu("Spelling") {
                toggleCell(.instantCorrect, .spelling, label: "Instant Correct")
                toggleCell(.autoComplete,   .spelling, label: "Auto-Complete")
            }

            // Grammar
            Menu("Grammar") {
                toggleCell(.instantCorrect, .grammar, label: "Instant Correct")
                toggleCell(.moreContext,    .grammar, label: "More Context")
            }

            // Markdown
            Menu("Markdown") {
                toggleCell(.autoComplete, .markdown, label: "Auto-Complete")
                toggleCell(.moreContext,  .markdown, label: "More Context")
            }

            // HTML
            Menu("HTML") {
                toggleCell(.autoComplete, .html, label: "Auto-Complete")
                toggleCell(.moreContext,  .html, label: "More Context")
            }

            // ASCII Art
            Menu("ASCII Art") {
                toggleCell(.autoComplete, .asciiArt, label: "Auto-Complete")
            }
        }
    }

    @ViewBuilder
    private func toggleCell(
        _ fn: WritingAssistFunction,
        _ lang: WritingAssistLanguage,
        label: String
    ) -> some View {
        Toggle(
            label,
            isOn: Binding(
                get: { settings.writingAssist.isEnabled(fn, for: lang) },
                set: { settings.setWritingAssist(fn, for: lang, to: $0) }
            )
        )
    }

    // MARK: - View menu

    private var viewMenu: some Commands {
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

    // MARK: - Window menu

    private var windowMenu: some Commands {
        Group {
            CommandGroup(replacing: .windowSize) {
                Button("Minimize") {
                    NSApp.keyWindow?.miniaturize(nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("Zoom") {
                    NSApp.keyWindow?.zoom(nil)
                }

                Divider()

                Button("Move Tab to New Window") {
                    // Stub: multi-window support is a future feature
                }
                .disabled(true)

                Button("Merge All Windows") {
                    // Stub: multi-window support is a future feature
                }
                .disabled(true)
            }

            CommandGroup(replacing: .windowList) {}
        }
    }

    // MARK: - Help menu

    private var helpMenu: some Commands {
        CommandGroup(replacing: .help) {
            Button("Sputnik Help") {
                appState.requestedHelpTopic = .sputnik
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Markdown Help") {
                appState.requestedHelpTopic = .markdown
            }

            Button("HTML Help") {
                appState.requestedHelpTopic = .html
            }

            Button("ASCII Art Help") {
                appState.requestedHelpTopic = .asciiArt
            }

            Button("Grammar Help") {
                appState.requestedHelpTopic = .grammar
            }

            Divider()

            Button("Release Notes") {
                // Stub: no release notes URL yet
            }
            .disabled(true)

            Button("Report an Issue…") {
                let subject = "Sputnik%20Issue%20Report"
                if let url = URL(string: "mailto:luke.isham@gmail.com?subject=\(subject)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Helpers

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            appState.openDocument(url: url)
        }
    }
}
