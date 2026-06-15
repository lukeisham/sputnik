import AppKit
import SwiftUI

struct FileMenuGroup: Commands {

    private let appState: AppState

    @Environment(\.openWindow) private var openWindow

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some Commands {
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
                    openDocument(appState: appState)
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

                Menu("Open Template") {
                    if appState.availableTemplates.isEmpty {
                        Text("No Templates")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.availableTemplates) { record in
                            Button(record.name) {
                                appState.openTemplate(record: record)
                            }
                        }
                    }
                }

                Divider()

                Button("Save As Template\u{2026}") {
                    saveAsTemplate(appState: appState)
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(appState.editorCommandHandler == nil)

                Menu("Remove Template") {
                    if appState.availableTemplates.isEmpty {
                        Text("No Templates")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.availableTemplates) { record in
                            Button(record.name) {
                                Task {
                                    do {
                                        try await appState.deleteTemplate(record: record)
                                    } catch {
                                        if let alert = error as? SputnikAlert {
                                            presentAlert(alert)
                                        }
                                    }
                                }
                            }
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
                    saveAs(appState: appState)
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
                    if let renderedAction = appState.pairedPreviewPrintAction {
                        presentPrintFormatChoice(renderedAction: renderedAction)
                    } else {
                        NSApp.sendAction(#selector(NSDocument.printDocument(_:)), to: nil, from: nil)
                    }
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }
}
