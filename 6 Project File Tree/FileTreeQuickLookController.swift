import AppKit
import Quartz
import SwiftUI

/// Controls Quick Look previews for the File Tree panel.
///
/// When the user presses space on a selected file in the tree, `toggleQuickLook()`
/// presents `QLPreviewPanel` for that file URL. Pressing space or escape again
/// dismisses it. This matches the standard Finder "spacebar to preview" gesture.
///
/// ## Constraints
/// - SR-2: Handles missing/deleted files gracefully — `NSURL` is a valid
///   `QLPreviewItem` even when the file no longer exists, and Quick Look
///   simply shows an empty preview.
/// - SW-3: Uses AppKit's `QLPreviewPanel` directly (no SwiftUI equivalent).
///   The controller is owned as a `@State` property by `FileTreePanel`.
@MainActor
public final class FileTreeQuickLookController: NSObject {

    /// The URLs of currently selected files. The Quick Look panel previews the
    /// first URL (index 0). Updated by `FileTreePanel` when selection changes.
    public var selectedURLs: [URL] = []

    private weak var panel: QLPreviewPanel?

    // MARK: - Public API

    /// Toggles the Quick Look panel: shows it if hidden, dismisses it if visible.
    public func toggleQuickLook() {
        guard !selectedURLs.isEmpty else { return }

        if let panel, panel.isVisible {
            panel.close()
            self.panel = nil
        } else {
            guard let qlPanel = QLPreviewPanel.shared() else { return }
            qlPanel.dataSource = self
            qlPanel.delegate = self
            qlPanel.makeKeyAndOrderFront(nil)
            qlPanel.reloadData()
            self.panel = qlPanel
        }
    }
}

// MARK: - QLPreviewPanelDataSource

@MainActor
extension FileTreeQuickLookController: QLPreviewPanelDataSource {

    public nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        // Safe to read selectedURLs here because QLPreviewPanel only calls
        // this from the main thread in practice.
        MainActor.assumeIsolated { self.selectedURLs.count }
    }

    public nonisolated func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int)
        -> QLPreviewItem
    {
        MainActor.assumeIsolated { self.selectedURLs[index] as NSURL }
    }
}

// MARK: - QLPreviewPanelDelegate

@MainActor
extension FileTreeQuickLookController: QLPreviewPanelDelegate {

    public nonisolated func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
        // Return false so QLPreviewPanel handles standard events (space, esc)
        // for dismiss and navigation. We only manage toggling in/out.
        false
    }
}
