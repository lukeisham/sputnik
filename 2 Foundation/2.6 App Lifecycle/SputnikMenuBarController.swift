import AppKit
import Observation

/// Manages the Sputnik satellite icon in the macOS menu bar for the lifetime of the app.
///
/// Responsibilities:
/// - Creates and holds an `NSStatusItem` on app launch (SR-1 — lives in Foundation 2.6).
/// - Observes `AppState.isProcessing`; when `true`, applies a `CABasicAnimation` rotation
///   to the status-item button's `CALayer` so the satellite visually "spins" during any
///   background operation. Uses the same flag as `StatusBarView` — single source of truth.
///
/// SW-3 rationale: `NSStatusItem` is AppKit-only; no SwiftUI equivalent exists.
///
/// - Note: PNG assets `SputnikMenuBar.png` (16 pt @1×) and `SputnikMenuBar@2x.png` (32 pt @2×)
///   must be present in the app's asset catalogue as imageset `SputnikMenuBar` with
///   `template-rendering-intent = template` so AppKit tints them for light/dark modes.
@MainActor
public final class SputnikMenuBarController {

    // MARK: - Private storage

    /// The status item held for the app's entire lifetime; `nil` if the system
    /// could not allocate one (edge-case on very old OS versions — SR-2).
    private var statusItem: NSStatusItem?

    /// Weak reference to the shared app state — prevents a retain cycle (SW-2).
    private weak var appState: AppState?

    /// Token returned by `withObservationTracking`; kept to extend the tracking lifetime.
    private var observationTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates the menu-bar controller and installs the status item immediately.
    ///
    /// - Parameter appState: The shared `AppState` whose `isProcessing` flag drives
    ///   the spin animation. Held weakly.
    public init(appState: AppState) {
        self.appState = appState
        installStatusItem()
        beginObservingProcessingState()
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Setup

    private func installStatusItem() {
        // NSStatusBar.system.statusItem can fail on extremely resource-constrained
        // systems — we guard against nil (SR-2) even though it is rare.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            // Could not obtain a button — status item is unusable; release it.
            NSStatusBar.system.removeStatusItem(item)
            return
        }

        // Use the named template image so AppKit auto-tints for light/dark (SR-5).
        if let image = NSImage(named: "SputnikMenuBar") {
            image.isTemplate = true
            button.image = image
        } else {
            // Fallback symbol so the item is still functional without the asset.
            button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                                   accessibilityDescription: "Sputnik")
            button.image?.isTemplate = true
        }

        button.toolTip = "Sputnik"
        statusItem = item
    }

    // MARK: - Processing-state observation

    /// Begins an async observation loop that tracks `AppState.isProcessing` and
    /// starts or stops the spin animation accordingly (SR-4 — @MainActor; SW-2 — [weak self]).
    private func beginObservingProcessingState() {
        guard let appState else { return }

        observationTask = Task { [weak self] in
            // Capture the previous value so we only act on transitions.
            var wasProcessing = appState.isProcessing
            applyAnimation(spinning: wasProcessing)

            // Poll via withObservationTracking inside a loop.
            while !Task.isCancelled {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = appState.isProcessing
                    } onChange: {
                        continuation.resume()
                    }
                }

                guard let self else { return }
                let isNow = appState.isProcessing
                if isNow != wasProcessing {
                    wasProcessing = isNow
                    await MainActor.run { self.applyAnimation(spinning: isNow) }
                }
            }
        }
    }

    // MARK: - Animation

    /// Starts or stops the satellite-spin `CABasicAnimation` on the button layer.
    ///
    /// Called on `@MainActor` so `CALayer` access is safe (SR-4).
    private func applyAnimation(spinning: Bool) {
        guard let layer = statusItem?.button?.layer else { return }

        if spinning {
            guard layer.animation(forKey: "sputnikSpin") == nil else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue    = 0
            spin.toValue      = -2 * Double.pi   // counter-clockwise like an orbiting satellite
            spin.duration     = 2.0
            spin.repeatCount  = .infinity
            spin.isRemovedOnCompletion = false
            layer.add(spin, forKey: "sputnikSpin")
        } else {
            layer.removeAnimation(forKey: "sputnikSpin")
        }
    }
}
