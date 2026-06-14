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
        // exists by the time we try to configure it. At make time `view.window`
        // is still nil (the view is not yet in the hierarchy), so fall back to the
        // key window here only — `updateNSView` uses the precise `nsView.window`.
        DispatchQueue.main.async { [weak view] in
            let window = view?.window ?? NSApp.keyWindow ?? NSApp.windows.first
            context.coordinator.updateWindow(title: title, url: documentURL, in: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Target the window that actually hosts this proxy view, not whichever window
        // happens to be key at render time (ISS-094) — the latter renames the wrong
        // window in any multi-window scenario.
        context.coordinator.updateWindow(title: title, url: documentURL, in: nsView.window)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {

        /// Applies the document URL and title to the given window — the window that
        /// hosts the proxy view, resolved by the caller from `nsView.window` (ISS-094).
        /// Called on every SwiftUI render where the inputs change.
        func updateWindow(title: String, url: URL?, in window: NSWindow?) {
            guard let window else { return }

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
