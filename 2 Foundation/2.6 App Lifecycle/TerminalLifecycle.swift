import Foundation

/// Allows `AppDelegate` to request a clean PTY shutdown without depending on
/// module 7 (`TerminalManager`) directly.
///
/// Module 7 implements this protocol and registers its instance with `AppDelegate`
/// during launch. Foundation owns the *protocol*; the concrete implementation lives in
/// the Terminal module (SR-1 — Foundation stays an interface layer).
@MainActor
public protocol TerminalLifecycle: AnyObject {
    /// Terminates all active PTY sessions and waits until they have exited.
    ///
    /// `AppDelegate.applicationShouldTerminate` calls this and returns `.terminateLater`
    /// while awaiting the result, then calls `NSApp.replyToApplicationShouldTerminate(true)`.
    func killAllPTYs() async
}
