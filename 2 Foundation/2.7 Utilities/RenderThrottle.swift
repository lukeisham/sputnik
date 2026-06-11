import Foundation

/// Throttles rapid render requests using generation-based coalescing.
///
/// Wraps `DebounceTimer` to prevent redundant re-renders when input arrives faster
/// than the render can complete (e.g., fast typing or terminal output floods).
/// If a newer generation is scheduled before the debounce fires, the old render
/// is cancelled and the new one is queued.
///
/// Usage:
/// ```swift
/// let throttle = RenderThrottle(delay: 0.1)
/// await throttle.throttle {
///     await viewModel.render(text)
/// }
/// ```
public final class RenderThrottle: @unchecked Sendable {

    /// Debounce delay in seconds. Default 0.1s.
    public var delay: TimeInterval {
        didSet {
            delay = max(0.01, min(2.0, delay)) // Clamp to [0.01, 2.0]
        }
    }

    // MARK: - Private state

    private let timer = DebounceTimer()
    private var generation: UInt64 = 0

    // MARK: - Public API

    /// Creates a new throttle with the given debounce delay.
    /// - Parameter delay: Quiet period (in seconds) before the render fires. Default 0.1s.
    public init(delay: TimeInterval = 0.1) {
        self.delay = max(0.01, min(2.0, delay))
    }

    /// Throttles a render closure using generation-based coalescing.
    ///
    /// If a newer call arrives before the debounce fires, the previous render is
    /// cancelled and this one is queued. Renders after the debounce are executed
    /// sequentially (one at a time).
    ///
    /// - Parameter render: Async closure that performs the render.
    public func throttle(render: @Sendable @escaping () async -> Void) {
        generation &+= 1
        let targetGeneration = generation

        timer.schedule(delay: delay) { [weak self] in
            Task {
                guard let self = self, self.generation == targetGeneration else {
                    // A newer render arrived; skip this one
                    return
                }
                await render()
            }
        }
    }

    /// Cancels any pending render without executing it.
    public func cancel() {
        timer.cancel()
    }

    deinit {
        timer.cancel()
    }
}
