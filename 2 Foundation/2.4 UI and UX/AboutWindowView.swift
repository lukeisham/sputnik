import SwiftUI

/// Custom About panel for Sputnik.
///
/// Displayed as a fixed-size SwiftUI `Window` scene (id: `"about"`) opened via
/// **App ▸ About Sputnik**. Shows the `SputnikLogo` asset, app name, version from
/// `CFBundleShortVersionString`, and a hard-coded credits block (SR-3 — not loaded
/// from disk at runtime; SR-5 — SwiftUI native).
///
/// Single-instance enforcement is handled by the scene itself via
/// `.handlesExternalEvents(matching: [])` in `SputnikApp`.
public struct AboutWindowView: View {

    // MARK: - Static credits (SR-3: hard-coded string — no runtime file load)

    private static let credits = """
        Native macOS productivity & development \
        environment that coordinates six concurrent \
        views: a Project File Tree, Text Editor \
        (Markdown/HTML/ASCII), Markdown Preview, \
        PDF Viewer, HTML Preview, and integrated \
        Zsh Terminal — within a unified, crash-resistant \
        layout, desgined for focused AI agent management, \
        and personal productivity. \

        Credits: Keith Foster · Nate Jones

        "Man, Sub-creator, the refracted Light …" — J.R.R. Tolkien
        """

    // MARK: - Version strings (read from bundle at init — safe, no I/O)

    private let versionString: String
    private let buildString: String

    // MARK: - Init

    /// Creates the About view. Version strings are sourced from the main bundle's
    /// `Info.plist` (no file I/O, SR-3).
    public init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        versionString = version
        buildString = build
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: SputnikSpacing.md) {
            // Logo — uses the SputnikLogo imageset (128 pt rendered size)
            Group {
                if let nsImage = NSImage(named: "SputnikLogo") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 128, height: 128)
                } else {
                    // Fallback symbol when the asset is absent during development.
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(SputnikColor.accent)
                }
            }

            // App name
            Text("Sputnik")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SputnikColor.primaryText)

            // Version
            Text("Version \(versionString) (\(buildString))")
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.secondaryText)

            Divider()

            // Credits block
            Text(Self.credits)
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // GitHub link (opens in default browser — no in-app web view)
            Link(
                "github.com/lukeisham/sputnik",
                destination: URL(string: "https://github.com/lukeisham/sputnik") ?? URL(
                    string: "https://github.com")!
            )
            .font(.system(size: SputnikFont.caption))

            Spacer(minLength: 0)

            // Dismiss button
            Button("OK") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
        .padding(SputnikSpacing.lg)
        .frame(width: 380, height: 460)
    }
}
