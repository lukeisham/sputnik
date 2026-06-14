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
    /// Decodes the raw byte stream into UTF-8 lines for the observer, carrying a
    /// partial multi-byte code point and a partial line across reads (ISS-079).
    private var lineDecoder = IncrementalLineDecoder()
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

    /// Splits raw output into complete lines for the AI output observer. Runs on the
    /// serial `queue`, so the `onLine` callbacks are delivered in order. The decoder
    /// carries a partial multi-byte code point and a partial line across reads, so a
    /// UTF-8 character split across two PTY reads is never dropped (ISS-079).
    private func splitLines(_ data: Data) {
        for line in lineDecoder.feed(data) { onLine(line) }
    }

    private func finishEOF() {
        guard !torndown else { return }
        torndown = true
        if let last = lineDecoder.flush() { onLine(last) }
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

/// Decodes a chunked byte stream into UTF-8 lines, carrying both a partial trailing
/// multi-byte code point and a partial trailing line across `feed` calls (ISS-079).
///
/// PTY reads land on arbitrary byte boundaries, so a single emoji or accented
/// character — or a single output line — can straddle two reads. Decoding each chunk
/// independently with `String(data:)` would fail on the split code point and silently
/// drop that chunk's lines. This decoder instead holds the incomplete tail until its
/// remaining bytes arrive. It is a plain value type with no fd or concurrency, so it
/// is unit-testable in isolation.
struct IncrementalLineDecoder {

    /// Bytes that did not yet form a complete UTF-8 sequence. At most three trailing
    /// bytes are ever held (the maximum continuation count in UTF-8).
    private var pendingBytes: [UInt8] = []

    /// The trailing text since the last newline, carried until a newline arrives.
    private var partialLine = ""

    /// Feeds a chunk and returns any newly completed lines, each with its trailing
    /// newline removed and control characters trimmed (matching the observer's
    /// expectation of clean, single lines).
    mutating func feed(_ data: Data) -> [String] {
        pendingBytes.append(contentsOf: data)

        // Hold back any trailing bytes that form an incomplete UTF-8 sequence.
        let holdBack = Self.incompleteTrailingByteCount(pendingBytes)
        let completeCount = pendingBytes.count - holdBack
        guard completeCount > 0 else { return [] }

        let decodable = pendingBytes[0..<completeCount]
        guard let text = String(bytes: decodable, encoding: .utf8) else {
            // Genuinely malformed (not merely incomplete) — drop the decoded span to
            // resync rather than wedge on bytes that will never decode.
            pendingBytes.removeFirst(completeCount)
            return []
        }
        pendingBytes.removeFirst(completeCount)

        let combined = partialLine + text
        let parts = combined.components(separatedBy: "\n")
        partialLine = parts.last ?? ""
        return parts.dropLast().map { $0.trimmingCharacters(in: .controlCharacters) }
    }

    /// Returns and clears any held partial line (text after the last newline). Call at
    /// EOF so a final unterminated line still reaches the observer. Incomplete trailing
    /// bytes (a code point cut off by EOF) are intentionally discarded — they can never
    /// decode.
    mutating func flush() -> String? {
        pendingBytes.removeAll()
        guard !partialLine.isEmpty else { return nil }
        let line = partialLine.trimmingCharacters(in: .controlCharacters)
        partialLine = ""
        return line
    }

    /// Returns how many trailing bytes of `bytes` form an **incomplete** UTF-8
    /// sequence — a lead byte plus fewer continuation bytes than its length requires.
    /// Those bytes must be carried to the next read. Returns `0` when the buffer ends
    /// on a complete code point (or on bytes that will simply fail to decode, which
    /// `feed` resyncs).
    static func incompleteTrailingByteCount(_ bytes: [UInt8]) -> Int {
        // Walk back over continuation bytes (0b10xxxxxx); a UTF-8 sequence has at
        // most three of them.
        var continuationCount = 0
        var index = bytes.count - 1
        while index >= 0, (bytes[index] & 0xC0) == 0x80, continuationCount < 3 {
            continuationCount += 1
            index -= 1
        }
        guard index >= 0 else { return continuationCount }  // all continuation: hold

        let lead = bytes[index]
        let expectedLength: Int
        if lead & 0x80 == 0x00 { expectedLength = 1 }        // 0xxxxxxx ASCII
        else if lead & 0xE0 == 0xC0 { expectedLength = 2 }   // 110xxxxx
        else if lead & 0xF0 == 0xE0 { expectedLength = 3 }   // 1110xxxx
        else if lead & 0xF8 == 0xF0 { expectedLength = 4 }   // 11110xxx
        else { return 0 }  // stray continuation / invalid lead — let decode resync

        let have = continuationCount + 1
        return have < expectedLength ? have : 0
    }
}
