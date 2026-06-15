import SwiftUI

/// SwiftUI overlay wrapper that mounts the correct minimap binder for the active panel.
///
/// Each panel drops this view via `.overlay(alignment: .trailing)`, gated on
/// `appState.minimapVisible`. The overlay selects the text binder when a scroll view
/// target is set and the web binder when a web view target is set.
///
/// One mount call per panel — consumer code is minimal and uniform (SR-1/SR-6).
public struct Minimap: View {

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    public init() {}

    public var body: some View {
        if appState.minimapVisible {
            HStack(spacing: 0) {
                Spacer()
                if let scrollView = appState.activeWindow?.minimapTargetScrollView {
                    MinimapScrollBinder(
                        target: scrollView,
                        settings: settings,
                        appState: appState
                    )
                    .frame(width: 90)
                } else if let webView = appState.activeWindow?.minimapTargetWebView {
                    MinimapWebBinder(
                        target: webView,
                        settings: settings,
                        appState: appState
                    )
                    .frame(width: 90)
                }
            }
        }
    }
}
