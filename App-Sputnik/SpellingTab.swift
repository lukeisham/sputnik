import FoundationModule
import SwiftUI

/// Settings for Apple's `NSTextView` spelling and grammar checker.
///
/// The checker runs on `.txt` and `.md` files only. The language follows the macOS
/// system setting.
struct SpellingTab: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Toggle(
                "Check spelling while typing",
                isOn: Binding(
                    get: { settings.systemSpellCheckEnabled },
                    set: { settings.setSystemSpellCheckEnabled($0) }
                )
            )
            Toggle(
                "Check grammar with spelling",
                isOn: Binding(
                    get: { settings.systemGrammarCheckEnabled },
                    set: { settings.setSystemGrammarCheckEnabled($0) }
                )
            )
        }
    }
}
