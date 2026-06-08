import Foundation

/// Observes a directory for external filesystem changes via `NSFilePresenter`
/// and emits the affected URL through an `AsyncStream`.
///
/// Callbacks arrive on an arbitrary `OperationQueue` from the file coordinator;
/// they are forwarded into the `AsyncStream` where the consumer decides how to
/// hop actors. The ViewModel subscribes and debounces before calling `refreshTree()`
/// (MR-2, SW-1).
public final class FileSystemWatcher: NSObject, NSFilePresenter, @unchecked Sendable {

    // MARK: - NSFilePresenter

    public var presentedItemURL: URL?

    public let presentedItemOperationQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.sputnik.filetree.presenter"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // MARK: - Change stream

    private var continuation: AsyncStream<URL>.Continuation?

    /// Emits a URL each time a change is detected in or to the watched item.
    public let changeStream: AsyncStream<URL>

    // MARK: - Init / deinit

    public init(url: URL) {
        var cont: AsyncStream<URL>.Continuation!
        changeStream = AsyncStream { cont = $0 }
        continuation = cont
        presentedItemURL = url
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        stop()
    }

    // MARK: - Stop

    /// Removes this presenter from the file coordinator and finishes the stream.
    public func stop() {
        NSFileCoordinator.removeFilePresenter(self)
        continuation?.finish()
        continuation = nil
    }

    // MARK: - NSFilePresenter callbacks

    public func presentedSubitemDidChange(at url: URL) {
        emit(url)
    }

    public func presentedSubitemDidAppear(at url: URL) {
        emit(url)
    }

    public func presentedItemDidChange() {
        if let url = presentedItemURL { emit(url) }
    }

    public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        if let url = presentedItemURL { emit(url) }
        completionHandler(nil)
    }

    // MARK: - Private

    private func emit(_ url: URL) {
        continuation?.yield(url)
    }
}
