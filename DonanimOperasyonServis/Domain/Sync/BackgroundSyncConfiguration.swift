import Foundation

/// Identifier and scheduling window for the app's background sync
/// task. Owned by DI so tests can substitute a fake scheduler
/// without talking to `BGTaskScheduler`.
struct BackgroundSyncConfiguration: Hashable, Sendable {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    var taskIdentifier: String
    /// `BGAppRefreshTaskRequest.earliestBeginDate` delay.
    var earliestBeginDelay: TimeInterval

    static let appRefresh = BackgroundSyncConfiguration(
        taskIdentifier: "com.donanimoperasyonservis.app.sync",
        earliestBeginDelay: 15 * 60
    )
}
