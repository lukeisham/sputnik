import Foundation

/// A fixed-capacity ring buffer of rendered terminal lines.
///
/// When a new line is appended past the capacity, the oldest line is silently
/// dropped. This bounds the memory used by scrollback regardless of output
/// volume (SR-3). Each line is a `[ScreenCell]` matching the grid width at
/// the time the line was scrolled off the active screen.
public struct ScrollbackBuffer: Sendable {

    // MARK: - Storage

    private var buffer: [[ScreenCell]]
    private var head: Int   // index of the oldest element (write cursor)
    private var count: Int

    // MARK: - Configuration

    /// Maximum number of lines held (from `TerminalProfile.scrollbackLineLimit`).
    public let capacity: Int

    // MARK: - Init

    public init(capacity: Int) {
        precondition(capacity > 0, "ScrollbackBuffer capacity must be positive")
        self.capacity = capacity
        self.buffer   = [[ScreenCell]](repeating: [], count: capacity)
        self.head     = 0
        self.count    = 0
    }

    // MARK: - Mutation

    /// Appends a line to the buffer, evicting the oldest line when full.
    public mutating func append(_ line: [ScreenCell]) {
        buffer[head] = line
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// Removes all lines.
    public mutating func clear() {
        buffer = [[ScreenCell]](repeating: [], count: capacity)
        head   = 0
        count  = 0
    }

    // MARK: - Access

    /// The number of lines currently stored.
    public var lineCount: Int { count }

    /// Returns a snapshot of all stored lines in oldest-to-newest order.
    ///
    /// `O(n)` copy — call only when the renderer needs to repaint.
    public func lines() -> [[ScreenCell]] {
        guard count > 0 else { return [] }
        let oldest = (head - count + capacity) % capacity
        var result = [[ScreenCell]]()
        result.reserveCapacity(count)
        for i in 0..<count {
            result.append(buffer[(oldest + i) % capacity])
        }
        return result
    }
}
