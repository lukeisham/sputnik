import Foundation

extension AppState {

    // MARK: - Crash recovery (ISS-108)

    /// Removes a single recovery entry after the user accepts or discards it.
    public func clearRecovery(name: String) {
        pendingRecoveryNames.removeAll { $0 == name }
    }
}
