import SwiftUI

/// Accessibility-aware view helpers shared by every module (SR-1).
///
/// macOS surfaces three system accessibility settings that Sputnik honours:
/// **Reduce Motion**, **Reduce Transparency**, and **Differentiate Without Color**.
/// SwiftUI already exposes each as an `@Environment` value, so this file does not
/// redefine them — it provides small, consistent helpers so panels apply them the
/// same way instead of each module re-implementing the check.
///
/// Usage:
/// ```swift
/// // Animate only when Reduce Motion is off:
/// border.accessibleAnimation(.easeInOut(duration: 0.15), value: role)
/// ```
extension View {

    /// Applies `animation` to `value` changes **only when Reduce Motion is off**.
    ///
    /// When the user has enabled *Reduce Motion* in System Settings ▸ Accessibility ▸
    /// Display, the animation is dropped to `nil` so the change happens instantly.
    ///
    /// - Parameters:
    ///   - animation: The animation to use when Reduce Motion is off.
    ///   - value: The equatable value whose changes drive the animation.
    /// - Returns: A view that animates respectfully of the Reduce Motion setting.
    public func accessibleAnimation<V: Equatable>(
        _ animation: Animation?,
        value: V
    ) -> some View {
        modifier(ReducedMotionAnimation(animation: animation, value: value))
    }
}

/// Backs ``SwiftUICore/View/accessibleAnimation(_:value:)``; reads the Reduce Motion
/// environment value and suppresses the animation when it is on.
private struct ReducedMotionAnimation<V: Equatable>: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
