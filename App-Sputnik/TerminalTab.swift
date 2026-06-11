import AppKit
import FoundationModule
import SwiftUI

struct TerminalTab: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            LabeledContent("Font") {
                HStack {
                    TextField(
                        "Font name",
                        text: Binding(
                            get: { settings.terminalFontName },
                            set: { settings.setTerminalFontName($0) })
                    )
                    .frame(width: 140)
                    TextField(
                        "Size",
                        value: Binding(
                            get: { settings.terminalFontSize },
                            set: { settings.setTerminalFontSize($0) }), format: .number
                    )
                    .frame(width: 48)
                }
            }

            LabeledContent("Scrollback lines") {
                TextField(
                    "",
                    value: Binding(
                        get: { settings.terminalScrollbackLimit },
                        set: { settings.setTerminalScrollbackLimit($0) }), format: .number
                )
                .frame(width: 80)
            }

            Divider()

            ColorPicker(
                "Foreground",
                selection: Binding(
                    get: {
                        Color(
                            red: settings.terminalForeground.red,
                            green: settings.terminalForeground.green,
                            blue: settings.terminalForeground.blue
                        )
                        .opacity(settings.terminalForeground.alpha)
                    },
                    set: { color in
                        guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                        settings.setTerminalForeground(
                            TerminalColor(
                                red: ns.redComponent, green: ns.greenComponent,
                                blue: ns.blueComponent, alpha: ns.alphaComponent
                            ))
                    }
                ))

            ColorPicker(
                "Background",
                selection: Binding(
                    get: {
                        Color(
                            red: settings.terminalBackground.red,
                            green: settings.terminalBackground.green,
                            blue: settings.terminalBackground.blue
                        )
                        .opacity(settings.terminalBackground.alpha)
                    },
                    set: { color in
                        guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                        settings.setTerminalBackground(
                            TerminalColor(
                                red: ns.redComponent, green: ns.greenComponent,
                                blue: ns.blueComponent, alpha: ns.alphaComponent
                            ))
                    }
                ))
        }
    }
}
