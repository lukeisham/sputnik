import SwiftUI

/// The bottom status bar showing satellite icon, Supporting AI model, Main AI state,
/// RAM and CPU.
///
/// **Layout:** 24pt fixed-height HStack pinned at the bottom of the main window.
/// Reads live values from `AppState`, `SettingsStore`, `SupportingAIMonitor`, and
/// `ProcessMonitor` via the SwiftUI environment.
///
/// **SW-3:** Pure SwiftUI — no AppKit or `NSViewRepresentable`.
///
/// **AI display (two segments):**
/// - **Supporting AI** (left): model name, shown only when a model is configured.
/// - **Main AI** (right of centre): model name + context % when a Main AI is active
///   in the terminal; shows `—` when none is detected.
public struct StatusBarView<Content: View>: View {

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(MainAIMonitor.self) private var mainAIMonitor

    /// Suppresses the satellite spin when *Reduce Motion* is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Adds a non-colour busy cue when *Differentiate Without Color* is on.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private let trailingContent: Content?

    /// Creates a status bar with optional trailing content (for F-8 terminal model).
    public init(@ViewBuilder trailingContent: () -> Content) {
        self.trailingContent = trailingContent()
    }

    public var body: some View {
        HStack(spacing: SputnikSpacing.sm) {
            // Satellite icon — static idle, spinning when processing
            satelliteIcon

            // Supporting AI model name (only if configured)
            if let model = supportingAIModel {
                Text(model)
                    .font(.system(size: SputnikFont.caption, design: .monospaced))
                    .foregroundStyle(SputnikColor.secondaryText)
                    .lineLimit(1)
                    .accessibilityLabel("Supporting AI model: \(model)")
            }

            // Main AI segment — shown only when a Main AI is active
            if let mainState = appState.mainAIState {
                Text(mainState.modelName)
                    .font(.system(size: SputnikFont.caption, design: .monospaced))
                    .foregroundStyle(SputnikColor.secondaryText)
                    .lineLimit(1)
                    .accessibilityLabel("Main AI model: \(mainState.modelName)")

                if let usage = mainState.usage {
                    Text(String(format: "%.0f%%", usage.percent))
                        .font(.system(size: SputnikFont.caption, design: .monospaced))
                        .foregroundStyle(SputnikColor.secondaryText)
                        .lineLimit(1)
                        .accessibilityLabel(
                            "Context used: \(String(format: "%.0f", usage.percent)) percent")
                } else if mainState.contextWindow != nil {
                    Text("CTX —")
                        .font(.system(size: SputnikFont.caption, design: .monospaced))
                        .foregroundStyle(SputnikColor.secondaryText)
                        .lineLimit(1)
                        .accessibilityLabel("Context usage unavailable")
                }
            } else {
                Text("—")
                    .font(.system(size: SputnikFont.caption, design: .monospaced))
                    .foregroundStyle(SputnikColor.secondaryText)
                    .lineLimit(1)
                    .help("No Main AI detected in terminal")
                    .accessibilityLabel("No Main AI detected in terminal")
            }

            Spacer()

            // RAM
            Text("\(monitor.ramMB) MB")
                .font(.system(size: SputnikFont.caption, design: .monospaced))
                .foregroundStyle(SputnikColor.secondaryText)
                .lineLimit(1)
                .accessibilityLabel("Memory: \(monitor.ramMB) megabytes")

            // CPU
            Text(String(format: "%.1f%%", monitor.cpuPercent))
                .font(.system(size: SputnikFont.caption, design: .monospaced))
                .foregroundStyle(SputnikColor.secondaryText)
                .lineLimit(1)
                .accessibilityLabel(
                    "CPU usage: \(String(format: "%.1f", monitor.cpuPercent)) percent")

            // Trailing content (F-8 terminal model segment)
            if let trailing = trailingContent {
                trailing
            }
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .frame(height: 24)
        .background(SputnikColor.secondaryBackground)
        .contextMenu {
            Button("Set Main AI Model…") {
                showManualModelAlert()
            }
            Divider()
            Button("Clear Main AI") {
                mainAIMonitor.clear()
            }
        }
    }

    // MARK: - Private helpers

    /// The antenna icon with a continuous rotation animation when processing.
    @ViewBuilder
    private var satelliteIcon: some View {
        let isProcessing = appState.isProcessing
        // Spin only when processing AND Reduce Motion is off.
        let shouldSpin = isProcessing && !reduceMotion

        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: SputnikFont.body))
            .foregroundStyle(isProcessing ? SputnikColor.accent : SputnikColor.secondaryText)
            .rotationEffect(.degrees(shouldSpin ? 360 : 0))
            .animation(
                shouldSpin
                    ? Animation.linear(duration: 2).repeatForever(autoreverses: false)
                    : .default,
                value: shouldSpin
            )
            .overlay(alignment: .topTrailing) {
                // Differentiate Without Color: a small badge marks the busy state
                // when colour alone (accent vs. secondary) cannot be relied upon.
                if isProcessing && differentiateWithoutColor {
                    Circle()
                        .fill(SputnikColor.primaryText)
                        .frame(width: 4, height: 4)
                        .offset(x: 2, y: -2)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Sputnik status")
            .accessibilityValue(isProcessing ? "Busy" : "Idle")
    }

    /// The configured Supporting AI model name, or `nil` when no model is set.
    private var supportingAIModel: String? {
        let name = settings.supportingAIConfig.modelName
        return name.isEmpty ? nil : name
    }

    /// Shows an NSAlert-style text entry for the user to manually declare a Main AI model.
    private func showManualModelAlert() {
        let alert = NSAlert()
        alert.messageText = "Set Main AI Model"
        alert.informativeText = "Enter the model name running in the terminal."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.placeholderString = "e.g. claude-sonnet-4-6"
        alert.accessoryView = textField
        textField.becomeFirstResponder()

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            mainAIMonitor.setManual(modelName: name)
        }
    }
}

// MARK: - Convenience initializers

extension StatusBarView where Content == EmptyView {
    /// Creates a status bar without trailing content.
    public init() {
        self.trailingContent = nil
    }
}
