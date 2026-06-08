import AppKit
import SwiftUI

/// Floating `NSPanel` that hosts the ASCII Studio (⌘⌥A or Format → ASCII Studio).
///
/// SW-3: `NSPanel` is required for a floating, non-activating tool window that stays
/// above the main document window. Panel chrome is the only AppKit here; all content
/// is SwiftUI via `ASCIIStudioView`.
@MainActor
public final class ASCIIStudioPanel: NSPanel {

    // MARK: - Shared instance

    public static let shared = ASCIIStudioPanel()

    // MARK: - Init

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
            styleMask: [
                .titled, .closable, .resizable,
                .utilityWindow, .nonactivatingPanel,
            ],
            backing: .buffered,
            defer:   true
        )
        title                   = "ASCII Studio"
        isFloatingPanel         = true
        becomesKeyOnlyIfNeeded  = true
        level                   = .floating
        center()
    }

    // MARK: - Public interface

    /// Opens the Studio panel wired to `textView`. Brings it to front if already open.
    public func open(for textView: NSTextView) {
        if contentView == nil || contentView is NSHostingView<ASCIIStudioView> == false {
            let view = ASCIIStudioView(textView: textView)
            contentView = NSHostingView(rootView: view)
        }
        makeKeyAndOrderFront(nil)
    }
}
