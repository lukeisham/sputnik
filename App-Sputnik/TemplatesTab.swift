import AppKit
import FoundationModule
import SwiftUI

/// The Templates tab in Sputnik Settings.
///
/// Shows the current template folder path and lets the user pick a custom folder
/// or reset to the default Application Support location.
struct TemplatesTab: View {

    let settings: SettingsStore
    let appState: AppState

    var body: some View {
        Form {
            Section {
                LabeledContent("Template Folder") {
                    HStack(spacing: 8) {
                        Text(displayPath)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 260, alignment: .leading)
                        Button("Choose\u{2026}") {
                            chooseFolder()
                        }
                    }
                }

                Button("Reset to Default") {
                    settings.setTemplateDirectoryURL(nil)
                    Task { await appState.applyTemplateDirectory(nil) }
                }
                .disabled(settings.templateDirectoryURL == nil)
            } footer: {
                Text("Templates are saved and loaded from this folder. Changes take effect immediately.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }

    // MARK: - Private

    /// The folder path shown to the user, abbreviated with `~` where possible.
    private var displayPath: String {
        let url = settings.templateDirectoryURL ?? TemplateStore.defaultDirectoryURL()
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a folder to use as the Templates directory:"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            settings.setTemplateDirectoryURL(url)
            Task { await appState.applyTemplateDirectory(url) }
        }
    }
}
