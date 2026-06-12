import FoundationModule
import SwiftUI

struct EditorTab: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Toggle(
                "Auto-save",
                isOn: Binding(
                    get: { settings.autoSaveEnabled }, set: { settings.setAutoSaveEnabled($0) }))
            Toggle(
                "Line numbers",
                isOn: Binding(
                    get: { settings.lineNumbersEnabled },
                    set: { settings.setLineNumbersEnabled($0) }))
            Toggle(
                "Word wrap",
                isOn: Binding(
                    get: { settings.wordWrapEnabled }, set: { settings.setWordWrapEnabled($0) }))
            Toggle(
                "Code block highlighting",
                isOn: Binding(
                    get: { settings.codeBlockHighlightEnabled },
                    set: { settings.setCodeBlockHighlightEnabled($0) }))
            Toggle(
                "HTML syntax checking",
                isOn: Binding(
                    get: { settings.htmlSyntaxCheckEnabled },
                    set: { settings.setHtmlSyntaxCheckEnabled($0) }))

            Divider()

            LabeledContent("Max file size (MB)") {
                TextField(
                    "Bytes",
                    value: Binding(
                        get: { settings.editorMaxFileSizeBytes / (1024 * 1024) },
                        set: { settings.setEditorMaxFileSizeBytes($0 * 1024 * 1024) }
                    ), format: .number
                )
                .frame(width: 64)
            }

            LabeledContent("ASCII trigger key") {
                TextField(
                    "Key",
                    text: Binding(
                        get: { settings.asciiTriggerKey }, set: { settings.setAsciiTriggerKey($0) })
                )
                .frame(width: 48)
            }

            Divider()

            Text("Auto-complete delay")
                .font(.headline)

            DebounceStepPicker(
                label: "Markdown",
                step: Binding(
                    get: { settings.markdownAutoCompleteStep },
                    set: { settings.setMarkdownAutoCompleteStep($0) }
                )
            )
            DebounceStepPicker(
                label: "ASCII",
                step: Binding(
                    get: { settings.asciiAutoCompleteStep },
                    set: { settings.setAsciiAutoCompleteStep($0) }
                )
            )
            DebounceStepPicker(
                label: "HTML",
                step: Binding(
                    get: { settings.htmlAutoCompleteStep },
                    set: { settings.setHtmlAutoCompleteStep($0) }
                )
            )
        }
    }
}
