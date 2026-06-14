import CoreServices
import Foundation
import FoundationModule

/// Sentinel emitted by `FileSystemWatcher` when the watched root is removed or
/// becomes inaccessible. Observers should stop the watcher and surface an error.
private let rootLostURL = URL(string: "sputnik://watchedRootLost")!

/// Observes a directory for external filesystem changes via `FSEventStream`
/// and emits the affected URL through an `AsyncStream`.
///
/// Unlike `NSFilePresenter`, `FSEventStream` fires for all writers — including
/// POSIX `rename`/`write` calls from terminal tools (`git`, `cp`, `rm -rf`,
/// build systems) that bypass file coordination (ISS-111a).
///
/// Events are delivered on a private `DispatchQueue` owned by the watcher.
/// `emit(_:)` holds `lock` before yielding so concurrent `stop()` + callback
/// calls cannot race on `continuation` (ISS-115).  Root removal is detected
/// via `kFSEventStreamEventFlagRootChanged` and reported as a sentinel URL
/// (ISS-114).
public final class FileSystemWatcher: @unchecked Sendable {

    // MARK: - Public

    /// The URL passed to `init`; exposed so callers can reuse it.
    public let watchedURL: URL

    /// Emits a URL each time a change is detected in the watched directory.
    /// Emits `sputnik://watchedRootLost` when the root disappears.
    public let changeStream: AsyncStream<URL>

    // MARK: - Private state

    private var continuation: AsyncStream<URL>.Continuation?
    private let lock = NSLock()             // guards `continuation` (ISS-115)
    private var eventStream: FSEventStreamRef?
    private var watchQueue: DispatchQueue?

    // MARK: - Init / deinit

    public init(url: URL) {
        self.watchedURL = url

        var cont: AsyncStream<URL>.Continuation!
        changeStream = AsyncStream { cont = $0 }
        continuation = cont

        setupStream(url: url)
    }

    deinit {
        stop()
    }

    // MARK: - Stop

    /// Stops the `FSEventStream` and finishes the `changeStream`.
    /// Safe to call multiple times.
    public func stop() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()

        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        watchQueue = nil
    }

    // MARK: - Internal emit (called from C callback)

    fileprivate func emit(_ url: URL) {
        lock.lock()
        continuation?.yield(url)
        lock.unlock()
    }

    fileprivate var rootPath: String { watchedURL.path }

    // MARK: - Setup

    private func setupStream(url: URL) {
        let paths = [url.path as CFString] as CFArray

        // Context passes `self` (unretained) to the C callback via `info`.
        // The callback lifetime is bounded by `FSEventStreamInvalidate`, called
        // from `stop()` before the watcher can be released, so the pointer is
        // always valid when the callback fires.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // `@convention(c)` closure — captures nothing; recovers `self` via `info`.
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()

            // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray of CFStrings.
            let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self)

            for i in 0..<numEvents {
                let flags = eventFlags[i]

                // Skip the synthetic "history done" marker.
                if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 { continue }

                // Root changed (directory renamed/deleted, or a parent renamed).
                if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                    watcher.emit(rootLostURL)
                    return
                }

                guard let rawPath = CFArrayGetValueAtIndex(cfPaths, i) else { continue }
                let path = unsafeBitCast(rawPath, to: CFString.self) as String

                // Root directory itself removed.
                if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0,
                   path == watcher.rootPath
                {
                    watcher.emit(rootLostURL)
                    return
                }

                watcher.emit(URL(fileURLWithPath: path))
            }
        }

        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,       // latency: batches rapid bursts (ISS-111a)
            createFlags
        ) else {
            SputnikLogger.fileTree.error("[FileSystemWatcher] FSEventStreamCreate failed for \(url.path)")
            return
        }
        eventStream = stream

        let queue = DispatchQueue(label: "com.sputnik.filetree.watcher", qos: .utility)
        watchQueue = queue
        FSEventStreamSetDispatchQueue(stream, queue)

        let started = FSEventStreamStart(stream)
        if started {
            SputnikLogger.fileTree.debug("[FileSystemWatcher] Watching \(url.path)")
        } else {
            SputnikLogger.fileTree.error("[FileSystemWatcher] FSEventStreamStart failed for \(url.path)")
        }
    }
}
