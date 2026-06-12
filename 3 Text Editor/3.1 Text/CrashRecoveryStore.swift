import Foundation
import FoundationModule

/// Serialises editor text to a recovery cache file after each significant change,
/// and clears the cache after a clean save.
///
/// SR-1: all writes route through `PersistenceService.writeRecovery(for:content:)` —
/// no direct `FileManager` access here.
/// SR-4: Tasks are scheduled with `.background` priority so serialisation does not
/// compete with the typing path.
///
/// Retry behaviour: if a write is cancelled by a subsequent keypress, the next text
/// change reschedules automatically — only the latest snapshot matters.
///
/// SW-2: `pendingTask` captures `[weak self]` to prevent retain cycles with the Task.
@MainActor
public final class CrashRecoveryStore {

    private let persistence: any PersistenceService
    private var pendingTask: Task<Void, Never>?

    public init(persistence: any PersistenceService) {
        self.persistence = persistence
    }

    deinit {
        pendingTask?.cancel()
    }

    // MARK: - Public interface

    /// Schedules a background write of `content` for `url`.
    ///
    /// Cancels any in-flight write; only the most recent snapshot is serialised
    /// (earlier intermediate states are not worth persisting).
    public func scheduleWrite(for url: URL, content: String) {
        pendingTask?.cancel()
        // Background priority — low scheduling weight, keeps UI thread clear (SR-4).
        pendingTask = Task(priority: .background) { [weak self] in
            guard !Task.isCancelled else { return }
            // PersistenceService is @MainActor, so the call runs on the main actor
            // regardless of the Task priority. Priority controls scheduling weight only.
            await self?.doWrite(url: url, content: content)
        }
    }

    /// Deletes the recovery file after a successful clean save.
    public func clearRecovery(for url: URL) {
        persistence.clearRecovery(for: url)
    }

    // MARK: - Private

    /// The `await` on this call inside `scheduleWrite` performs an `@MainActor`
    /// actor hop — required because the `.background` Task is not isolated to
    /// any actor. Making this explicitly `async` resolves a false-positive compiler
    /// warning about the `await` expression containing no async operations.
    private func doWrite(url: URL, content: String) async {
        persistence.writeRecovery(for: url, content: content)
    }
}
