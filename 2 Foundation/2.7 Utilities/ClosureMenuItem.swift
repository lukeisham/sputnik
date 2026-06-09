import AppKit

/// An `NSMenuItem` that invokes a stored closure on activation, avoiding the need for
/// each host to wire `@objc` selectors.
///
/// This is a general-purpose utility (SR-6: single responsibility). Use it anywhere
/// you need an `NSMenuItem` whose action is a simple closure rather than a target-action
/// pair with a formal selector.
///
/// **Usage:**
/// ```swift
/// let item = ClosureMenuItem(title: "Do Something") { print("clicked") }
/// ```
@MainActor
public final class ClosureMenuItem: NSMenuItem {

    /// The closure invoked when this menu item is activated.
    /// Captured at creation time; runs on `@MainActor` via the `action` selector.
    private let actionClosure: () -> Void

    /// Creates a menu item whose action runs the given closure on `@MainActor`.
    /// - Parameters:
    ///   - title: The menu item's title.
    ///   - keyEquivalent: Optional keyboard shortcut (default `""`).
    ///   - closure: The closure to run on activation.
    public init(title: String, keyEquivalent: String = "", closure: @escaping () -> Void) {
        self.actionClosure = closure
        super.init(title: title, action: #selector(handleAction), keyEquivalent: keyEquivalent)
        self.target = self
    }

    @available(*, unavailable)
    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleAction() {
        actionClosure()
    }
}
