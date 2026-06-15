import FoundationModule
import SwiftUI

/// A read-only reference tab listing all keyboard shortcuts grouped by menu.
///
/// Displayed as the seventh tab in the Settings window. No `SettingsStore` mutation
/// — this is purely informational. Shortcut data comes from `KeyboardShortcutCatalog`
/// in Foundation 2.0.
struct ShortcutsTab: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(KeyboardShortcutCatalog.grouped, id: \.group) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            LabeledContent(entry.title) {
                                Text(entry.keys)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(section.group)
                            .font(.headline)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
