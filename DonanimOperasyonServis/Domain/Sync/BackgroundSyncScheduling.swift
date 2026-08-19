import Foundation

/// A single background-task execution token. Domain never imports
/// `BackgroundTasks`; Infrastructure wraps `BGAppRefreshTask`.
protocol BackgroundSyncTaskHandle: Sendable {
    /// Idempotent. Safe to call from expiration and from the drain
    /// completion path.
    func complete(success: Bool)
}

/// Registers and reschedules the OS background sync task.
protocol BackgroundSyncScheduling: Sendable {
    var configuration: BackgroundSyncConfiguration { get }
    func register(_ handler: @escaping @Sendable (any BackgroundSyncTaskHandle) async -> Void)
    func scheduleNext()
}
