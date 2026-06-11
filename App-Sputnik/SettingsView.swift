import FoundationModule
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SupportingAIMonitor.self) private var supportingAIMonitor

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
        }
        .frame(width: 460)
        .padding(SputnikSpacing.lg)
    }
}
