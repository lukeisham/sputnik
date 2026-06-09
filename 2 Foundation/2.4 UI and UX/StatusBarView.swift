import SwiftUI

/// The bottom status bar showing satellite icon, AI model, context usage, RAM and CPU.
///
/// **Layout:** 24pt fixed-height HStack pinned at the bottom of the main window.
/// Reads live values from `AppState`, `SettingsStore`, and `ProcessMonitor` via the
/// SwiftUI environment.
///
/// **SW-3:** Pure SwiftUI — no AppKit or `NSViewRepresentable`.
///
/// **F-8 compatibility:** Accepts optional `trailingContent` for the terminal model
/// segment to be placed on the trailing side of the bar.
public struct StatusBarView<Content: View>: View {

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(ProcessMonitor.self) private var monitor

    private let trailingContent: Content?

    /// Creates a status bar with optional trailing content (for F-8 terminal model).
    public init(@ViewBuilder trailingContent: () -> Content) {
        self.trailingContent = trailingContent()
    }

    public var body: some View {
        HStack(spacing: SputnikSpacing.sm) {
            // Satellite icon — static idle, spinning when processing
            satelliteIcon

            // AI model name (only if configured)
            if let model = configuredModel {
                Text(model)
                    .font(.system(size: SputnikFont.caption, design: .monospaced))
                    .foregroundStyle(SputnikColor.secondaryText)
                    .lineLimit(1)

                // Context % — conditional on both model and non-nil usage
                if let usage = appState.contextUsage {
                    Text(String(format: "%.0f%%", usage.percent))
                        .font(.system(size: SputnikFont.caption, design: .monospaced))
                        .foregroundStyle(SputnikColor.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            // RAM
            Text("\(monitor.ramMB) MB")
                .font(.system(size: SputnikFont.caption, design: .monospaced))
                .foregroundStyle(SputnikColor.secondaryText)
                .lineLimit(1)

            // CPU
            Text(String(format: "%.1f%%", monitor.cpuPercent))
                .font(.system(size: SputnikFont.caption, design: .monospaced))
                .foregroundStyle(SputnikColor.secondaryText)
                .lineLimit(1)

            // Trailing content (F-8 terminal model segment)
            if let trailing = trailingContent {
                trailing
            }
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .frame(height: 24)
        .background(SputnikColor.secondaryBackground)
    }

    // MARK: - Private helpers

    /// The satellite icon with a continuous rotation animation when processing.
    @ViewBuilder
    private var satelliteIcon: some View {
        let isProcessing = appState.isProcessing

        Image(systemName: "satellite")
            .font(.system(size: SputnikFont.body))
            .foregroundStyle(isProcessing ? SputnikColor.accent : SputnikColor.secondaryText)
            .rotationEffect(.degrees(isProcessing ? 360 : 0))
            .animation(
                isProcessing
                    ? Animation.linear(duration: 2).repeatForever(autoreverses: false)
                    : .default,
                value: isProcessing
            )
    }

    /// The configured AI model name, or `nil` when no model is set.
    private var configuredModel: String? {
        let name = settings.aiConfig.modelName
        return name.isEmpty ? nil : name
    }
}

// MARK: - Convenience initializers

extension StatusBarView where Content == EmptyView {
    /// Creates a status bar without trailing content.
    public init() {
        self.trailingContent = nil
    }
}
