import FoundationModule
import SwiftUI

struct SpellingTab: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Toggle(
                "Spell checking",
                isOn: Binding(
                    get: { settings.spellCheckEnabled }, set: { settings.setSpellCheckEnabled($0) })
            )
            Toggle(
                "Grammar checking",
                isOn: Binding(
                    get: { settings.grammarCheckEnabled },
                    set: { settings.setGrammarCheckEnabled($0) }))

            Divider()

            Text("Auto-complete delay")
                .font(.headline)

            DebounceStepPicker(
                label: "Spelling",
                step: Binding(
                    get: { settings.spellingAutoCompleteStep },
                    set: { settings.setSpellingAutoCompleteStep($0) }
                )
            )

            LabeledContent("Language (BCP-47)") {
                TextField(
                    "System default",
                    text: Binding(
                        get: { settings.spellCheckLocale ?? "" },
                        set: { settings.setSpellCheckLocale($0.isEmpty ? nil : $0) }
                    )
                )
                .frame(width: 140)
            }
        }
    }
}
