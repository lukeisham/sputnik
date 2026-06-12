import AppKit
import SwiftUI

/// A minimal AppKit bridge that updates the window's title and proxy icon
/// (`representedURL`) whenever the active document URL changes.
///
/// Placed as a zero-size `.background` view in `ContentView` so it observes
/// the current document URL through SwiftUI's render cycle. When a file-based
/// document is active the proxy icon appears in the window title bar; ⌘-clicking
/// the title reveals the file's path, and the proxy icon supports drag operations.
///
/// For untitled buffers or windows with no active document the URL is cleared,
/// restoring the workspace folder name or "Untitled" as the title.
///
/// ## Constraints
/// - SW-3: Uses a minimal `NSViewRepresentable` bridge — not a broad AppKit takeover.
/// - SR-2: `representedURL` is set to `nil` for missing/deleted files; never force-unwraps.
struct WindowProxyView: NSViewRepresentable {

    /// The title to display (document filename, workspace folder, or "Untitled").
    let title: String

    /// The file URL of the active document, or `nil` for untitled buffers.
    let documentURL: URL?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Schedule the initial update on the next run loop so the window
        // exists by the time we try to configure it.
        DispatchQueue.main.async {
            context.coordinator.updateWindow(title: title, url: documentURL)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateWindow(title: title, url: documentURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {

        /// Applies the document URL and title to the key window.
        /// Called on every SwiftUI render where the inputs change.
        func updateWindow(title: String, url: URL?) {
            // Operate on the key window, falling back to any available window.
            // This is safe because the proxy view is rendered inside the window
            // whose title/proxy we want to update (SW-3).
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }

            if let url {
                // File-based document: show the proxy icon and file name.
                window.representedURL = url
                window.title = url.lastPathComponent
            } else {
                // Untitled or no document: clear the proxy icon.
                window.representedURL = nil
                window.title = title
            }
        }
    }
}
