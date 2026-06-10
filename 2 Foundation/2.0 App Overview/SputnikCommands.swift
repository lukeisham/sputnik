import AppKit
import SwiftUI

/// Wires all six macOS menu bar menus to `AppState` and `SettingsStore` actions.
///
/// Attach to `WindowGroup` via `.commands { SputnikCommands(appState:settings:) }` in `SputnikApp`.
/// Dependencies are passed directly because `Commands` bodies run outside the SwiftUI view
/// hierarchy and cannot reliably read `@Environment` values injected on a `WindowGroup`.
public struct SputnikCommands: Commands {

    private let appState: AppState
    private let settings: SettingsStore
    private let router: AppInterPanelRouter

    @Environment(\.openWindow) private var openWindow

    public init(appState: AppState, settings: SettingsStore, router: AppInterPanelRouter) {
        self.appState = appState
        self.settings = settings
        self.router = router
    }

    public var body: some Commands {
        sputnikMenu
        fileMenu
        editMenu
        formatMenu
        viewMenu
        windowMenu
        helpMenu
    }

    // MARK: - Sputnik menu

    private var sputnikMenu: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sputnik") {
                openWindow(id: "about")
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
                    let ws = appState.createWindow()
                    openWindow(id: "main", value: ws.id)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

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
                    Task {
                        do {
                            try await appState.editorCommandHandler?.save()
                        } catch {
                            if let sputnikAlert = error as? SputnikAlert {
                                presentAlert(sputnikAlert)
                            }
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.editorCommandHandler == nil)

                Button("Save As…") {
                    saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState.editorCommandHandler == nil)

                Divider()

                Button("Render as HTML") {
                    Task {
                        do {
                            try await appState.editorCommandHandler?.renderAsHTML()
                        } catch {
                            if let sputnikAlert = error as? SputnikAlert {
                                presentAlert(sputnikAlert)
                            }
                        }
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(appState.editorCommandHandler == nil)

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
                        NSApp.sendAction(
                            #selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Button("Find and Replace…") {
                        NSApp.sendAction(
                            #selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])

                    Button("Find Next") {
                        NSApp.sendAction(
                            #selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("g", modifiers: .command)

                    Button("Find Previous") {
                        NSApp.sendAction(
                            #selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                }

                Menu("Spelling and Grammar") {
                    Button("Check Now") {
                        NSApp.sendAction(
                            #selector(NSTextView.checkSpelling(_:)), to: nil, from: nil)
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
                toggleCell(.autoComplete, .spelling, label: "Auto-Complete")
            }

            // Grammar
            Menu("Grammar") {
                toggleCell(.instantCorrect, .grammar, label: "Instant Correct")
                toggleCell(.moreContext, .grammar, label: "More Context")
            }

            // Markdown
            Menu("Markdown") {
                toggleCell(.autoComplete, .markdown, label: "Auto-Complete")
                toggleCell(.moreContext, .markdown, label: "More Context")
            }

            // HTML
            Menu("HTML") {
                toggleCell(.autoComplete, .html, label: "Auto-Complete")
                toggleCell(.moreContext, .html, label: "More Context")
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

    // MARK: - Format menu

    private var formatMenu: some Commands {
        CommandMenu("Format") {
            Button("ASCII Studio") {
                Task {
                    do {
                        try await appState.editorCommandHandler?.showASCIIStudio()
                    } catch {
                        if let sputnikAlert = error as? SputnikAlert {
                            presentAlert(sputnikAlert)
                        }
                    }
                }
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(appState.editorCommandHandler == nil)
        }
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
                    // Route through the router so the dirty-guard fires for unsaved tabs (ISS-020).
                    Task {
                        if let newWindowID = await router.moveActiveTabToNewWindow() {
                            openWindow(id: "main", value: newWindowID)
                        }
                    }
                }

                Button("Merge All Windows") {
                    let allWindows = appState.orderedWindowIDs.compactMap {
                        appState.windowForID($0)
                    }
                    guard allWindows.count > 1 else { return }
                    guard let target = appState.activeWindow ?? allWindows.first else { return }
                    // Collect all tabs from other windows into the target.
                    let windowsToMerge = allWindows.filter { $0.id != target.id }
                    for window in windowsToMerge {
                        for doc in window.openDocuments {
                            if !target.openDocuments.contains(where: {
                                $0.url == doc.url && $0.url != nil
                            }) {
                                target.openDocuments.append(doc)
                            }
                        }
                        // Close the NSWindow tagged with this WindowState's UUID (ISS-018).
                        // Windows are tagged via NSWindow.identifier in SputnikApp.onAppear.
                        if let nsWindow = NSApp.windows.first(where: {
                            $0.identifier?.rawValue == window.id.uuidString
                        }) {
                            nsWindow.close()
                        }
                        appState.closeWindow(window.id)
                    }
                    // Kill terminal PTYs after closing windows (killAllPTYs is async).
                    Task {
                        for window in windowsToMerge {
                            await window.terminalManager?.killAllPTYs()
                        }
                    }
                }
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

    private func saveAs() {
        guard let currentURL = appState.currentlyOpenFile else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = currentURL.lastPathComponent
        panel.begin { response in
            guard response == .OK, let newURL = panel.url else { return }
            Task {
                do {
                    try await appState.editorCommandHandler?.saveAs(to: newURL)
                } catch {
                    if let sputnikAlert = error as? SputnikAlert {
                        presentAlert(sputnikAlert)
                    }
                }
            }
        }
    }

    private func presentAlert(_ alert: SputnikAlert) {
        let panel = NSAlert()
        panel.messageText = alert.title
        panel.informativeText = alert.message
        panel.alertStyle = .warning
        panel.addButton(withTitle: "OK")
        panel.runModal()
    }
}
