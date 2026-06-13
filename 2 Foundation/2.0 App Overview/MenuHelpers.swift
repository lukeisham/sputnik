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

/// Presents a two-button alert asking whether to print as plain text or rendered preview.
/// Called by FileMenuGroup when a preview panel is paired with the active document.
@MainActor
func presentPrintFormatChoice(renderedAction: @escaping () -> Void) {
    guard let window = NSApp.keyWindow else {
        renderedAction()
        return
    }
    let alert = NSAlert()
    alert.messageText = "Print"
    alert.informativeText = "Print the document as plain text or as the rendered preview?"
    alert.addButton(withTitle: "Rendered")
    alert.addButton(withTitle: "Plain Text")
    alert.alertStyle = .informational
    alert.beginSheetModal(for: window) { response in
        if response == .alertFirstButtonReturn {
            renderedAction()
        } else {
            NSApp.sendAction(#selector(NSDocument.printDocument(_:)), to: nil, from: nil)
        }
    }
}
