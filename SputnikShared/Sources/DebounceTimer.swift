import Foundation

/// Delays execution of a closure until a quiet period has elapsed, cancelling any
/// previously scheduled work when called again before the delay expires.
///
/// Uses `Task.sleep` (Swift Concurrency) — no `DispatchQueue` involved. The work closure
/// runs on `@MainActor` since all call sites are `@MainActor`-isolated.
@MainActor
public final class DebounceTimer {

    private var pendingTask: Task<Void, Never>?

    /// Creates a new `DebounceTimer`.
    public init() {}

    /// Cancels any pending work and schedules `work` to run after `delay` seconds.
    ///
    /// If `schedule` is called again before `delay` elapses, the previous closure is
    /// discarded and the timer resets.
    /// - Parameters:
    ///   - delay: Quiet period in seconds before `work` is executed.
    ///   - work:  The closure to run after the quiet period.
    public func schedule(delay: TimeInterval, work: @escaping @Sendable () -> Void) {
        pendingTask?.cancel()
        pendingTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                work()
            } catch {
                // Task was cancelled — discard silently.
            }
        }
    }

    /// Cancels any pending work without running it.
    public func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    deinit {
        pendingTask?.cancel()
    }
}
