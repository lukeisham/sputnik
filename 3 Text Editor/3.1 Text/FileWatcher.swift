import AppKit
import Foundation
import FoundationModule

/// Watches the open file for external changes using `NSFilePresenter` (MR-2).
///
/// When the file changes on disk, the user is prompted via a native `NSAlert` to
/// reload from disk or keep their local version. The prompt routes through `SputnikAlert`
/// for consistent error presentation.
///
/// SW-2: `FileWatcher` is a long-lived observer — all closures and presenter callbacks
/// capture `[weak self]` to prevent retain cycles.
// @unchecked Sendable is required: NSFilePresenter requires NSObject, and Sendable
// conformance cannot be compiler-verified for ObjC-bridged types. All mutable state
// (onReload, suppressNextChange) is accessed from @MainActor callbacks, making this safe.
public final class FileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {

    // MARK: - NSFilePresenter

    public let presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue = .main

    // MARK: - Callbacks

    /// Called after the user confirms they want to reload from disk.
    public var onReload: (() -> Void)?

    /// Temporarily suppress reload prompts (e.g. when saving locally).
    /// Reset after the notification fires.
    private var suppressNextChange = false

    // MARK: - Init

    public init(url: URL) {
        self.presentedItemURL = url
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    /// Suppress the next file-change notification (used when saving locally).
    public func setSuppressNextChange() {
        suppressNextChange = true
    }

    // MARK: - NSFilePresenter callbacks

    /// Called by the file system when the file has been externally modified.
    public func presentedItemDidChange() {
        // Hop to @MainActor; the presenter callback may arrive on any queue (SW-2).
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.suppressNextChange {
                self.suppressNextChange = false
                return
            }
            self.promptReload()
        }
    }

    // MARK: - Private

    @MainActor
    private func promptReload() {
        guard let url = presentedItemURL else { return }

        let alert = NSAlert()
        alert.messageText =
            SputnikAlert.custom(
                title: "File Changed",
                message: ""
            ).title
        alert.informativeText = """
            "\(url.lastPathComponent)" was modified by another process. \
            Reload from disk, or keep your local version?
            """
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Keep My Version")

        if alert.runModal() == .alertFirstButtonReturn {
            onReload?()
        }
    }
}
