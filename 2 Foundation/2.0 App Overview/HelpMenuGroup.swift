import AppKit
import SwiftUI

struct HelpMenuGroup: Commands {

    private let appState: AppState
    private let settings: SettingsStore

    init(appState: AppState, settings: SettingsStore) {
        self.appState = appState
        self.settings = settings
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

            Button("JSON Help") {
                appState.requestedHelpTopic = .json
            }

            Button("ASCII Art Help") {
                appState.requestedHelpTopic = .asciiArt
            }

            Button("Grammar Help") {
                appState.requestedHelpTopic = .grammar
            }

            Divider()

            interactionSubmenu

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

    // MARK: - Interaction Submenu

    /// The "Interaction ▶" submenu, parallel to the "More-Context" pattern.
    /// Per-language toggles reading/writing `WritingAssistMatrix.interaction`.
    @ViewBuilder
    private var interactionSubmenu: some View {
        Menu("Interaction") {
            Menu("Markdown") {
                toggleInteraction(.markdown)
            }
            Menu("HTML") {
                toggleInteraction(.html)
            }
            Menu("ASCII Art") {
                toggleInteraction(.asciiArt)
            }
            Menu("JSON") {
                toggleInteraction(.json)
            }
            Menu("Grammar") {
                toggleInteraction(.grammar)
            }
            Divider()
            Button("All On") {
                settings.setWritingAssistAllInteraction(to: true)
            }
            Button("All Off") {
                settings.setWritingAssistAllInteraction(to: false)
            }
        }
    }

    @ViewBuilder
    private func toggleInteraction(_ lang: WritingAssistLanguage) -> some View {
        Toggle(
            lang.rawValue,
            isOn: Binding(
                get: { settings.writingAssist.isEnabled(.interaction, for: lang) },
                set: { settings.setWritingAssist(.interaction, for: lang, to: $0) }
            )
        )
    }
}
