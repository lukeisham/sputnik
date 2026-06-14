import Foundation

/// Bridges a PTY master file descriptor to GCD event sources for non-blocking
/// reads and writes.
///
/// **MR-3 documented exception:** PTY file-descriptor readiness has no
/// `async/await` equivalent, so this is the one place the Terminal module bridges
/// through `DispatchSource` instead of Swift Concurrency. All mutable state
/// (`pendingWrite`, the source references, `torndown`, `partialLine`) is touched
/// **only** on the private serial `queue`; the type is `@unchecked Sendable`
/// because that confinement — not the compiler — guarantees data-race safety.
///
/// Replaces the old blocking `FileHandle.availableData` reader that parked a
/// cooperative-pool thread for the session's lifetime (ISS-068) and the blocking
/// `FileHandle.write` that wedged the actor when the input buffer filled (ISS-074).
///
/// The channel takes ownership of the master fd once `activate()` is called and
/// closes it from the read source's cancel handler — the only safe place to close
/// a descriptor still backing a live Dispatch source.
final class PTYChannel: @unchecked Sendable {

    // MARK: - Immutable configuration

    private let fd: Int32
    private let queue: DispatchQueue
    private let onData: @Sendable (Data) -> Void
    private let onLine: @Sendable (String) -> Void
    private let onEOF: @Sendable () -> Void

    // MARK: - Queue-confined mutable state

    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var pendingWrite = Data()
    private var partialLine = ""
    private var torndown = false

    /// Bytes read per readability event — one PTY buffer's worth. The read source
    /// re-fires while the descriptor stays readable, so larger bursts drain over
    /// successive events. Coalescing many small shell writes into one chunk here is
    /// the read-side throttle referenced by ISS-073.
    private static let readChunk = 65_536

    // MARK: - Init

    init(
        fd: Int32,
        onData: @escaping @Sendable (Data) -> Void,
        onLine: @escaping @Sendable (String) -> Void,
        onEOF: @escaping @Sendable () -> Void
    ) {
        self.fd = fd
        self.queue = DispatchQueue(label: "com.sputnik.terminal.pty-io.\(fd)")
        self.onData = onData
        self.onLine = onLine
        self.onEOF = onEOF
    }

    // MARK: - Lifecycle

    /// Marks the fd non-blocking and starts the read source.
    func activate() {
        queue.async { [self] in
            let descriptor = fd
            let flags = fcntl(descriptor, F_GETFL)
            if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }

            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.handleReadable() }
            source.setCancelHandler { Darwin.close(descriptor) }  // sole fd-close site
            readSource = source
            source.resume()
        }
    }

    /// Queues bytes for non-blocking write, draining what it can immediately and
    /// installing a write source for the remainder on `EAGAIN` (ISS-074).
    func enqueueWrite(_ data: Data) {
        queue.async { [self] in
            guard !torndown else { return }
            pendingWrite.append(data)
            drainWrites()
        }
    }

    /// Cancels both sources; the read source's cancel handler closes the fd.
    /// Idempotent.
    func teardown() {
        queue.async { [self] in
            guard !torndown else { return }
            torndown = true
            shutdownSources()
        }
    }

    // MARK: - Queue-confined helpers

    private func handleReadable() {
        var buffer = [UInt8](repeating: 0, count: Self.readChunk)
        let n = buffer.withUnsafeMutableBytes { ptr in
            Darwin.read(fd, ptr.baseAddress, Self.readChunk)
        }
        if n > 0 {
            let chunk = Data(buffer[0..<n])
            onData(chunk)
            splitLines(chunk)
        } else if n == 0 {
            // Clean EOF — the last slave copy closed (shell exited, ISS-070).
            finishEOF()
        } else {
            // n < 0
            if errno == EAGAIN || errno == EINTR { return }
            // EIO and friends mean the slave is gone — treat as end of stream.
            finishEOF()
        }
    }

    private func drainWrites() {
        while !pendingWrite.isEmpty {
            let n = pendingWrite.withUnsafeBytes { ptr in
                Darwin.write(fd, ptr.baseAddress, pendingWrite.count)
            }
            if n > 0 {
                pendingWrite.removeFirst(n)
            } else if n < 0 && errno == EINTR {
                continue
            } else if n < 0 && errno == EAGAIN {
                installWriteSourceIfNeeded()  // wait for writability
                return
            } else {
                // Unrecoverable write error (fd closed) — drop the buffer.
                pendingWrite.removeAll()
                return
            }
        }
        // Fully drained — the write source has done its job.
        writeSource?.cancel()
        writeSource = nil
    }

    private func installWriteSourceIfNeeded() {
        guard writeSource == nil, !torndown else { return }
        let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drainWrites() }
        writeSource = source
        source.resume()
    }

    /// Splits raw output into complete lines for the AI output observer, holding a
    /// partial trailing line across reads. Runs on the serial `queue`, so the
    /// `onLine` callbacks are delivered in order.
    private func splitLines(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let combined = partialLine + text
        let parts = combined.components(separatedBy: "\n")
        partialLine = parts.last ?? ""
        for line in parts.dropLast() {
            onLine(line.trimmingCharacters(in: .controlCharacters))
        }
    }

    private func finishEOF() {
        guard !torndown else { return }
        torndown = true
        if !partialLine.isEmpty {
            onLine(partialLine.trimmingCharacters(in: .controlCharacters))
            partialLine = ""
        }
        onEOF()
        shutdownSources()
    }

    /// Cancels the write source, then the read source whose cancel handler closes
    /// the fd. If the read source was never created, closes the fd directly.
    private func shutdownSources() {
        writeSource?.cancel()
        writeSource = nil
        if let read = readSource {
            read.cancel()  // cancel handler closes the fd
            readSource = nil
        } else {
            Darwin.close(fd)
        }
    }
}
