import FoundationModule
import SwiftUI

/// A font name + size field pair bound to a mutable `EditorFont`.
func fontField(font: EditorFont, onChange: @escaping (EditorFont) -> Void) -> some View {
    HStack {
        TextField(
            "PostScript name",
            text: Binding(
                get: { font.postScriptName },
                set: { onChange(EditorFont(postScriptName: $0, pointSize: font.pointSize)) }
            )
        )
        .frame(width: 160)
        TextField(
            "pt",
            value: Binding(
                get: { font.pointSize },
                set: {
                    onChange(
                        EditorFont(
                            postScriptName: font.postScriptName,
                            pointSize: CGFloat($0 ?? font.pointSize)))
                }
            ),
            format: .number
        )
        .frame(width: 48)
    }
}

/// A per-panel font override row with a "Use global" clear button and a colour well.
func perPanelFontSection(
    font: EditorFont,
    isOverride: Bool,
    onFontChange: @escaping (EditorFont) -> Void,
    onClear: @escaping () -> Void,
    background: Color,
    onBackgroundChange: @escaping (Color) -> Void
) -> some View {
    VStack(alignment: .leading, spacing: SputnikSpacing.sm) {
        HStack {
            fontField(font: font, onChange: onFontChange)
            if isOverride {
                Button("Use global") {
                    onClear()
                }
                .buttonStyle(.plain)
                .foregroundStyle(SputnikColor.accent)
                .controlSize(.small)
            }
        }

        ColorPicker(
            "Background",
            selection: Binding(
                get: { background },
                set: { onBackgroundChange($0) }
            )
        )
    }
    .padding(.leading, 8)
}
