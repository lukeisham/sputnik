import Foundation
import AppKit

/// Watches the open file for external changes using `NSFilePresenter` (MR-2).
///
/// When the file changes on disk, the user is prompted via a native `NSAlert` to
/// reload from disk or keep their local version. The prompt routes through `SputnikAlert`
/// for consistent error presentation.
///
/// SW-2: `FileWatcher` is a long-lived observer — all closures and presenter callbacks
/// capture `[weak self]` to prevent retain cycles.
public final class FileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {

    // MARK: - NSFilePresenter

    public let presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue = .main

    // MARK: - Callbacks

    /// Called after the user confirms they want to reload from disk.
    public var onReload: (() -> Void)?

    // MARK: - Init

    public init(url: URL) {
        self.presentedItemURL = url
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    // MARK: - NSFilePresenter callbacks

    /// Called by the file system when the file has been externally modified.
    public func presentedItemDidChange() {
        // Hop to @MainActor; the presenter callback may arrive on any queue (SW-2).
        Task { @MainActor [weak self] in
            self?.promptReload()
        }
    }

    // MARK: - Private

    @MainActor
    private func promptReload() {
        guard let url = presentedItemURL else { return }

        let alert = NSAlert()
        alert.messageText     = SputnikAlert.custom(
            title:   "File Changed",
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
