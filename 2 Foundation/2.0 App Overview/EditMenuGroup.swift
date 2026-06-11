import AppKit
import SwiftUI

struct EditMenuGroup: Commands {

    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var body: some Commands {
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

    private var writingAssistanceMenu: some View {
        Menu("Writing Assistance") {
            Button("All On") {
                settings.setWritingAssistMatrix(.allOn())
            }
            Button("All Off") {
                settings.setWritingAssistMatrix(.allOff())
            }

            Divider()

            Menu("Spelling") {
                toggleCell(.instantCorrect, .spelling, label: "Instant Correct")
                toggleCell(.autoComplete, .spelling, label: "Auto-Complete")
            }

            Menu("Grammar") {
                toggleCell(.instantCorrect, .grammar, label: "Instant Correct")
                toggleCell(.moreContext, .grammar, label: "More Context")
            }

            Menu("Markdown") {
                toggleCell(.autoComplete, .markdown, label: "Auto-Complete")
                toggleCell(.moreContext, .markdown, label: "More Context")
            }

            Menu("HTML") {
                toggleCell(.autoComplete, .html, label: "Auto-Complete")
                toggleCell(.moreContext, .html, label: "More Context")
            }

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
}
