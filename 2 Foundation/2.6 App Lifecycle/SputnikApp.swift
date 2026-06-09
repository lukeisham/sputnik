import AppKit
import SwiftUI

/// The single app entry point.
///
/// Wires together Foundation's shared objects (`AppState`, `SettingsStore`,
/// `FilePersistenceService`, `AppDelegate`) and injects them into the SwiftUI environment.
/// The `WindowGroup` uses `.handlesExternalEvents` to enforce a single-window model —
/// files opened from Finder are routed through `InterPanelRouter` (module 2.1) rather than
/// opening a second window.
@main
public struct SputnikApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Shared objects

    private let persistence = FilePersistenceService()

    @State private var appState = AppState()
    @State private var settingsStore: SettingsStore
    @State private var processMonitor = ProcessMonitor()  // F-5

    // MARK: - Init

    public init() {
        let persistence = FilePersistenceService()
        let store = SettingsStore(persistence: persistence)
        _settingsStore = State(initialValue: store)

        // Wire dependencies into AppDelegate before any lifecycle method fires.
        // AppDelegate is constructed before `init` returns, so this is safe.
    }

    // MARK: - Scenes

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(settingsStore)
                .environment(processMonitor)  // F-5
                .onAppear {
                    wireAppDelegate()
                }
        }
        .commands { SputnikCommands(appState: appState, settings: settingsStore) }
        .handlesExternalEvents(matching: [])  // Single-window enforcement

        // F-2: About window — fixed size, single instance, no toolbar.
        Window("About Sputnik", id: "about") {
            AboutWindowView()
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])  // Second activation raises existing window.

        Settings {
            SettingsView()
                .environment(settingsStore)
        }
    }

    // MARK: - Private helpers

    /// Passes shared objects to `AppDelegate` after the app finishes launching.
    /// Called once from `ContentView.onAppear`.
    private func wireAppDelegate() {
        appDelegate.persistenceService = persistence
        appDelegate.appState = appState  // F-1: needed for SputnikMenuBarController
        appDelegate.processMonitor = processMonitor  // F-5: start/stop polling lifecycle
        // terminalLifecycle is wired by module 7 when TerminalManager is created.
    }
}

// MARK: - Settings view

private struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            EditorTab(settings: settings)
                .tabItem { Label("Editor", systemImage: "text.alignleft") }
            SpellingTab(settings: settings)
                .tabItem { Label("Spelling & Grammar", systemImage: "checkmark.bubble") }
            TerminalTab(settings: settings)
                .tabItem { Label("Terminal", systemImage: "terminal") }
            AISettingsView(settings: settings)
                .tabItem { Label("AI", systemImage: "brain") }
        }
        .frame(width: 460)
        .padding(SputnikSpacing.lg)
    }
}

// MARK: - Appearance tab

private struct AppearanceTab: View {
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
        }
    }

    // MARK: - Shared helpers

    /// A font name + size field pair bound to a mutable `EditorFont`.
    private func fontField(font: EditorFont, onChange: @escaping (EditorFont) -> Void) -> some View
    {
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
                        onChange(EditorFont(postScriptName: font.postScriptName, pointSize: $0))
                    }
                ),
                format: .number
            )
            .frame(width: 48)
        }
    }

    /// A per-panel font override row with a "Use global" clear button and a colour well.
    private func perPanelFontSection(
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
}

// MARK: - Editor tab

private struct EditorTab: View {
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

            LabeledContent("Markdown debounce (s)") {
                TextField(
                    "",
                    value: Binding(
                        get: { settings.markdownDebounceInterval },
                        set: { settings.setMarkdownDebounceInterval($0) }), format: .number
                )
                .frame(width: 64)
            }
            LabeledContent("ASCII debounce (s)") {
                TextField(
                    "",
                    value: Binding(
                        get: { settings.asciiDebounceInterval },
                        set: { settings.setAsciiDebounceInterval($0) }), format: .number
                )
                .frame(width: 64)
            }
            LabeledContent("HTML debounce (s)") {
                TextField(
                    "",
                    value: Binding(
                        get: { settings.htmlDebounceInterval },
                        set: { settings.setHtmlDebounceInterval($0) }), format: .number
                )
                .frame(width: 64)
            }
        }
    }
}

// MARK: - Spelling & Grammar tab

private struct SpellingTab: View {
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

            LabeledContent("Spell-check debounce (s)") {
                TextField(
                    "",
                    value: Binding(
                        get: { settings.spellCheckDebounceInterval },
                        set: { settings.setSpellCheckDebounceInterval($0) }), format: .number
                )
                .frame(width: 64)
            }

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

// MARK: - Terminal tab

private struct TerminalTab: View {
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
