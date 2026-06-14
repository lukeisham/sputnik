import Foundation
import FoundationModule

/// Watches the open file for external changes using a `DispatchSource` file-object source.
///
/// Opens the file with `O_EVTONLY` so it can be watched without preventing unmounts,
/// then registers for `.write`, `.delete`, `.rename`, and `.extend` events. All events
/// are delivered on the main queue.
///
/// - `onChanged`: fires when the file content is modified externally.
/// - `onDeleted`: fires when the file is deleted or moved away.
///
/// Call `suppressOnce()` immediately before each programmatic save so the kernel-level
/// notification from that write consumes a suppression credit rather than triggering a
/// spurious reload prompt (ISS-113).
///
/// @unchecked Sendable: all mutable state (`onChanged`, `onDeleted`, `suppressCount`)
/// is only written and read from `@MainActor`-isolated call sites and the main-queue
/// event handler — no concurrent access.
public final class FileWatcher: @unchecked Sendable {

    // MARK: - Callbacks

    /// Called when the file is modified externally (write / extend event).
    public var onChanged: (() -> Void)?

    /// Called when the file is deleted or moved away (delete / rename event).
    public var onDeleted: (() -> Void)?

    // MARK: - Private state

    private var source: DispatchSourceFileSystemObject?
    private let fd: Int32
    private var suppressCount = 0

    // MARK: - Init

    public init(url: URL) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        let capturedFD = fd
        src.setEventHandler { [weak self] in self?.handleEvent() }
        src.setCancelHandler { close(capturedFD) }
        src.resume()
        source = src
    }

    // MARK: - Deinit

    deinit {
        source?.cancel()   // triggers cancelHandler which closes the fd
    }

    // MARK: - API

    /// Consume one suppression credit before each programmatic write (ISS-113).
    ///
    /// Each credit suppresses exactly one kernel notification. An atomic save that
    /// produces two notifications (write + rename) requires two calls — one for each.
    /// A POSIX rename that produces zero notifications lets the credit drain harmlessly
    /// on the next real external change (one spurious suppression at most).
    public func suppressOnce() {
        suppressCount += 1
    }

    // MARK: - Private

    private func handleEvent() {
        guard let source else { return }

        // Consume a suppression credit before categorising the event so that
        // an atomic-save rename does not reach onDeleted.
        if suppressCount > 0 {
            suppressCount -= 1
            return
        }

        let data = source.data
        if data.contains(.delete) || data.contains(.rename) {
            onDeleted?()
        } else {
            onChanged?()
        }
    }
}
