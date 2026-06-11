import AppKit
import SwiftUI

@MainActor
func openDocument(appState: AppState) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        appState.openDocument(url: url)
    }
}

@MainActor
func saveAs(appState: AppState) {
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

@MainActor
func presentAlert(_ alert: SputnikAlert) {
    let panel = NSAlert()
    panel.messageText = alert.title
    panel.informativeText = alert.message
    panel.alertStyle = .warning
    panel.addButton(withTitle: "OK")
    panel.runModal()
}
