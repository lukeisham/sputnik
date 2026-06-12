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
    public let profile: TerminalProfile
    public let onKeyInput: (Data) -> Void
    public let onResize: (UInt16, UInt16) -> Void
    public let onTextViewCreated: ((TerminalTextView) -> Void)?

    public init(
        snapshot: EmulatorSnapshot?,
        profile: TerminalProfile,
        onKeyInput: @escaping (Data) -> Void,
        onResize: @escaping (UInt16, UInt16) -> Void,
        onTextViewCreated: ((TerminalTextView) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.profile = profile
        self.onKeyInput = onKeyInput
        self.onResize = onResize
        self.onTextViewCreated = onTextViewCreated
    }

    // MARK: - NSViewRepresentable

    public func makeNSView(context: Context) -> TerminalTextView {
        let view = TerminalTextView(frame: .zero)
        view.onKeyInput = onKeyInput
        view.onResize = onResize
        onTextViewCreated?(view)
        return view
    }

    public func updateNSView(_ nsView: TerminalTextView, context: Context) {
        nsView.onKeyInput = onKeyInput
        nsView.onResize = onResize
        if let snap = snapshot {
            nsView.update(snapshot: snap, profile: profile)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    /// Currently unused placeholder retained for future extension.
    /// The view owns its own frame observation (see `TerminalTextView.viewDidMoveToWindow`).
    public final class Coordinator: NSObject {
        override init() {}
    }
}
