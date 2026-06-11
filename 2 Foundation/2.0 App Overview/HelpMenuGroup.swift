import AppKit
import SwiftUI

struct HelpMenuGroup: Commands {

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some Commands {
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
}
