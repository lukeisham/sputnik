import AppKit
import SwiftUI

struct FormatMenuGroup: Commands {

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some Commands {
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
}
