import AppKit
import SwiftUI

/// Bridges an `NSScrollView` (editor, Markdown preview, JSON viewer) to a `MinimapView`.
///
/// Observes text changes (throttled, off-main rebuild) and bounds changes on the owning
/// clip view. Holds a **weak** reference to the target scroll view and removes all
/// observers in `dismantleNSView` (SW-2, ISS-093).
///
/// Reuses the ISS-063 scroll-sync bounds-observer pattern.
public struct MinimapScrollBinder: NSViewRepresentable {

    /// Weak reference to the target scroll view.
    let target: NSScrollView?

    /// The settings store, read for `minimapOpacity`.
    let settings: SettingsStore

    /// The app state, read for `minimapVisible`.
    let appState: AppState

    public init(target: NSScrollView?, settings: SettingsStore, appState: AppState) {
        self.target = target
        self.settings = settings
        self.appState = appState
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    public func makeNSView(context: Context) -> MinimapView {
        let view = MinimapView()
        view.onScrollToFraction = { [weak target] fraction in
            guard let target else { return }
            let docH = (target.documentView?.frame.height ?? 0)
            let viewH = target.contentView.bounds.height
            let maxScroll = max(0, docH - viewH)
            let y = CGFloat(fraction) * maxScroll
            target.contentView.scroll(to: NSPoint(x: 0, y: y))
            target.reflectScrolledClipView(target.contentView)
        }
        view.minimapOpacity = settings.minimapOpacity

        // Register observers.
        context.coordinator.registerObservers(target: target, minimapView: view)
        context.coordinator.rebuildModel(target: target)

        return view
    }

    public func updateNSView(_ nsView: MinimapView, context: Context) {
        nsView.minimapOpacity = settings.minimapOpacity

        // Re-register if the target changed.
        if context.coordinator.observedScrollView !== target {
            context.coordinator.removeObservers()
            context.coordinator.registerObservers(target: target, minimapView: nsView)
            context.coordinator.rebuildModel(target: target)
        }
    }

    public static func dismantleNSView(
        _ nsView: MinimapView, coordinator: Coordinator
    ) {
        coordinator.removeObservers()
        nsView.onScrollToFraction = nil
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator {
        private var textObserverToken: NSObjectProtocol?
        private var boundsObserverToken: NSObjectProtocol?
        private weak var minimapView: MinimapView?
        private(set) weak var observedScrollView: NSScrollView?
        private let builder = MinimapModelBuilder()
        private let settings: SettingsStore
        private var rebuildTask: Task<Void, Never>?

        init(settings: SettingsStore) {
            self.settings = settings
        }

        func registerObservers(target: NSScrollView?, minimapView: MinimapView) {
            self.minimapView = minimapView
            self.observedScrollView = target

            guard let target else { return }

            let clipView = target.contentView
            clipView.postsBoundsChangedNotifications = true

            // Bounds change → update viewport fraction.
            boundsObserverToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateViewport(target: target)
                }
            }

            // Text change → schedule rebuild (throttled, off-main).
            textObserverToken = NotificationCenter.default.addObserver(
                forName: NSText.didChangeNotification,
                object: target.documentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRebuild(target: target)
                }
            }
        }

        func removeObservers() {
            if let token = textObserverToken {
                NotificationCenter.default.removeObserver(token)
                textObserverToken = nil
            }
            if let token = boundsObserverToken {
                NotificationCenter.default.removeObserver(token)
                boundsObserverToken = nil
            }
            rebuildTask?.cancel()
            rebuildTask = nil
            observedScrollView = nil
            minimapView = nil
        }

        // MARK: - Model rebuild

        func rebuildModel(target: NSScrollView?) {
            guard let target, target.documentView is NSTextView else {
                minimapView?.model = .empty
                return
            }
            scheduleRebuild(target: target)
        }

        private func scheduleRebuild(target: NSScrollView) {
            rebuildTask?.cancel()
            guard let textView = target.documentView as? NSTextView else { return }
            let text = textView.string
            rebuildTask = Task { [weak self] in
                let model = MinimapModelBuilder().build(from: text)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.minimapView?.model = model
                }
            }
        }

        // MARK: - Viewport update

        private func updateViewport(target: NSScrollView) {
            let docH = target.documentView?.frame.height ?? 0
            let viewH = target.contentView.bounds.height
            let maxScroll = max(0, docH - viewH)
            let fraction =
                maxScroll > 0
                ? target.contentView.bounds.origin.y / maxScroll
                : 0
            minimapView?.viewportFraction = max(0, min(1.0, fraction))
        }
    }
}
