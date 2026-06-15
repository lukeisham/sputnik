import FoundationModule
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SupportingAIMonitor.self) private var supportingAIMonitor
    @Environment(AppState.self) private var appState

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
            SupportingAISettingsView(settings: settings, supportingAIMonitor: supportingAIMonitor)
                .tabItem { Label("AI", systemImage: "brain") }
            TemplatesTab(settings: settings, appState: appState)
                .tabItem { Label("Templates", systemImage: "doc.badge.plus") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 460)
        .padding(SputnikSpacing.lg)
    }
}
