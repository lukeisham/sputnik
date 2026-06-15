import FoundationModule
import SwiftUI

struct AppearanceTab: View {
    let settings: SettingsStore

    @State private var textEditorExpanded = false
    @State private var markdownPreviewExpanded = false
    @State private var htmlPreviewExpanded = false

    var body: some View {
        Form {
            Picker(
                "Theme", selection: Binding(get: { settings.theme }, set: { settings.setTheme($0) })
            ) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Text(t.rawValue.capitalized).tag(t)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            LabeledContent("Editor Font") {
                fontField(font: settings.editorFont, onChange: { settings.setEditorFont($0) })
            }

            Divider()
            Text("Per-Panel Overrides")
                .font(.headline)
                .foregroundStyle(SputnikColor.primaryText)

            DisclosureGroup("Text Editor", isExpanded: $textEditorExpanded) {
                perPanelFontSection(
                    font: settings.textEditorFont ?? settings.editorFont,
                    isOverride: settings.textEditorFont != nil,
                    onFontChange: { settings.setTextEditorFont($0) },
                    onClear: { settings.setTextEditorFont(nil) },
                    background: settings.textEditorBackground,
                    onBackgroundChange: { settings.setTextEditorBackground($0) }
                )
            }

            DisclosureGroup("Markdown Preview", isExpanded: $markdownPreviewExpanded) {
                perPanelFontSection(
                    font: settings.markdownPreviewFont ?? settings.editorFont,
                    isOverride: settings.markdownPreviewFont != nil,
                    onFontChange: { settings.setMarkdownPreviewFont($0) },
                    onClear: { settings.setMarkdownPreviewFont(nil) },
                    background: settings.markdownPreviewBackground,
                    onBackgroundChange: { settings.setMarkdownPreviewBackground($0) }
                )
            }

            DisclosureGroup("HTML Preview", isExpanded: $htmlPreviewExpanded) {
                perPanelFontSection(
                    font: settings.htmlPreviewFont ?? settings.editorFont,
                    isOverride: settings.htmlPreviewFont != nil,
                    onFontChange: { settings.setHtmlPreviewFont($0) },
                    onClear: { settings.setHtmlPreviewFont(nil) },
                    background: settings.htmlPreviewBackground,
                    onBackgroundChange: { settings.setHtmlPreviewBackground($0) }
                )
            }

            Divider()

            LabeledContent("Minimap Opacity") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { settings.minimapOpacity },
                            set: { settings.setMinimapOpacity($0) }
                        ),
                        in: 0.15...1.0
                    )
                    Text(String(format: "%.0f%%", settings.minimapOpacity * 100))
                        .font(.system(size: SputnikFont.caption))
                        .foregroundStyle(SputnikColor.secondaryText)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}
