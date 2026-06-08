import AppKit
import SwiftUI

/// SwiftUI bridge to `TerminalTextView`.
///
/// **SW-3 justification (required at this call site):** The ANSI terminal
/// renderer (`TerminalTextView`) is implemented as a raw `NSView` because it
/// needs per-cell glyph and colour control at a throughput that SwiftUI layout
/// cannot match. This `NSViewRepresentable` is the minimal documented bridge
/// between the SwiftUI view hierarchy and the AppKit renderer — it contains no
/// terminal logic of its own (SR-6).
@MainActor
public struct TerminalRenderer: NSViewRepresentable {

    public let snapshot: EmulatorSnapshot?
    public let profile:  TerminalProfile
    public let onKeyInput: (Data) -> Void
    public let onResize: (UInt16, UInt16) -> Void

    public init(
        snapshot: EmulatorSnapshot?,
        profile:  TerminalProfile,
        onKeyInput: @escaping (Data) -> Void,
        onResize:   @escaping (UInt16, UInt16) -> Void
    ) {
        self.snapshot   = snapshot
        self.profile    = profile
        self.onKeyInput = onKeyInput
        self.onResize   = onResize
    }

    // MARK: - NSViewRepresentable

    public func makeNSView(context: Context) -> TerminalTextView {
        let view = TerminalTextView(frame: .zero)
        view.onKeyInput = onKeyInput
        return view
    }

    public func updateNSView(_ nsView: TerminalTextView, context: Context) {
        if let snap = snapshot {
            nsView.update(snapshot: snap, profile: profile)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(onResize: onResize) }

    // MARK: - Coordinator

    /// Observes the NSView's frame changes and forwards resize events to the session.
    public final class Coordinator: NSObject {
        private let onResize: (UInt16, UInt16) -> Void
        private var observer: NSObjectProtocol?

        init(onResize: @escaping (UInt16, UInt16) -> Void) {
            self.onResize = onResize
        }
    }
}
