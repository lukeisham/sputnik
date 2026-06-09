import SwiftUI
import AppKit

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
                .onAppear {
                    wireAppDelegate()
                }
        }
        .commands { SputnikCommands(appState: appState, settings: settingsStore) }
        .handlesExternalEvents(matching: [])   // Single-window enforcement

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
        appDelegate.appState           = appState   // F-1: needed for SputnikMenuBarController
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
        }
        .frame(width: 460)
        .padding(SputnikSpacing.lg)
    }
}

// MARK: - Appearance tab

private struct AppearanceTab: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Picker("Theme", selection: Binding(get: { settings.theme }, set: { settings.setTheme($0) })) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Text(t.rawValue.capitalized).tag(t)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            LabeledContent("Editor Font") {
                HStack {
                    TextField("PostScript name", text: Binding(
                        get: { settings.editorFont.postScriptName },
                        set: { settings.setEditorFont(EditorFont(postScriptName: $0, pointSize: settings.editorFont.pointSize)) }
                    ))
                    .frame(width: 160)
                    TextField("pt", value: Binding(
                        get: { settings.editorFont.pointSize },
                        set: { settings.setEditorFont(EditorFont(postScriptName: settings.editorFont.postScriptName, pointSize: $0)) }
                    ), format: .number)
                    .frame(width: 48)
                }
            }
        }
    }
}

// MARK: - Editor tab

private struct EditorTab: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Toggle("Auto-save", isOn: Binding(get: { settings.autoSaveEnabled }, set: { settings.setAutoSaveEnabled($0) }))
            Toggle("Line numbers", isOn: Binding(get: { settings.lineNumbersEnabled }, set: { settings.setLineNumbersEnabled($0) }))
            Toggle("Word wrap", isOn: Binding(get: { settings.wordWrapEnabled }, set: { settings.setWordWrapEnabled($0) }))

            Divider()

            LabeledContent("Max file size (MB)") {
                TextField("Bytes", value: Binding(
                    get: { settings.editorMaxFileSizeBytes / (1024 * 1024) },
                    set: { settings.setEditorMaxFileSizeBytes($0 * 1024 * 1024) }
                ), format: .number)
                .frame(width: 64)
            }

            LabeledContent("ASCII trigger key") {
                TextField("Key", text: Binding(get: { settings.asciiTriggerKey }, set: { settings.setAsciiTriggerKey($0) }))
                    .frame(width: 48)
            }

            Divider()

            LabeledContent("Markdown debounce (s)") {
                TextField("", value: Binding(get: { settings.markdownDebounceInterval }, set: { settings.setMarkdownDebounceInterval($0) }), format: .number)
                    .frame(width: 64)
            }
            LabeledContent("ASCII debounce (s)") {
                TextField("", value: Binding(get: { settings.asciiDebounceInterval }, set: { settings.setAsciiDebounceInterval($0) }), format: .number)
                    .frame(width: 64)
            }
            LabeledContent("HTML debounce (s)") {
                TextField("", value: Binding(get: { settings.htmlDebounceInterval }, set: { settings.setHtmlDebounceInterval($0) }), format: .number)
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
            Toggle("Spell checking", isOn: Binding(get: { settings.spellCheckEnabled }, set: { settings.setSpellCheckEnabled($0) }))
            Toggle("Grammar checking", isOn: Binding(get: { settings.grammarCheckEnabled }, set: { settings.setGrammarCheckEnabled($0) }))

            Divider()

            LabeledContent("Spell-check debounce (s)") {
                TextField("", value: Binding(get: { settings.spellCheckDebounceInterval }, set: { settings.setSpellCheckDebounceInterval($0) }), format: .number)
                    .frame(width: 64)
            }

            LabeledContent("Language (BCP-47)") {
                TextField("System default", text: Binding(
                    get: { settings.spellCheckLocale ?? "" },
                    set: { settings.setSpellCheckLocale($0.isEmpty ? nil : $0) }
                ))
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
                    TextField("Font name", text: Binding(get: { settings.terminalFontName }, set: { settings.setTerminalFontName($0) }))
                        .frame(width: 140)
                    TextField("Size", value: Binding(get: { settings.terminalFontSize }, set: { settings.setTerminalFontSize($0) }), format: .number)
                        .frame(width: 48)
                }
            }

            LabeledContent("Scrollback lines") {
                TextField("", value: Binding(get: { settings.terminalScrollbackLimit }, set: { settings.setTerminalScrollbackLimit($0) }), format: .number)
                    .frame(width: 80)
            }

            Divider()

            ColorPicker("Foreground", selection: Binding(
                get: {
                    Color(red: settings.terminalForeground.red,
                          green: settings.terminalForeground.green,
                          blue:  settings.terminalForeground.blue)
                        .opacity(settings.terminalForeground.alpha)
                },
                set: { color in
                    guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                    settings.setTerminalForeground(TerminalColor(
                        red: ns.redComponent, green: ns.greenComponent,
                        blue: ns.blueComponent, alpha: ns.alphaComponent
                    ))
                }
            ))

            ColorPicker("Background", selection: Binding(
                get: {
                    Color(red: settings.terminalBackground.red,
                          green: settings.terminalBackground.green,
                          blue:  settings.terminalBackground.blue)
                        .opacity(settings.terminalBackground.alpha)
                },
                set: { color in
                    guard let ns = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                    settings.setTerminalBackground(TerminalColor(
                        red: ns.redComponent, green: ns.greenComponent,
                        blue: ns.blueComponent, alpha: ns.alphaComponent
                    ))
                }
            ))
        }
    }
}
