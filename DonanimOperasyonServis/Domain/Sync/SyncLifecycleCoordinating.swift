import Foundation

/// Coordinates app launch, foreground, network recovery, and
/// background tasks with the **existing** `SyncManaging` +
/// `SyncRecoveryHandling`. This is not a second SyncManager.
protocol SyncLifecycleCoordinating: Sendable {
    func startObservingReachability() async
    func handleLaunch(now: Date) async
    func handleBecomeActive(now: Date) async
    func handleNetworkBecameReachable(now: Date) async
    func handleBackgroundTask(_ task: any BackgroundSyncTaskHandle, now: Date) async
}

extension SyncLifecycleCoordinating {
    func handleLaunch() async {
        await handleLaunch(now: Date())
    }

    func handleBecomeActive() async {
        await handleBecomeActive(now: Date())
    }

    func handleNetworkBecameReachable() async {
        await handleNetworkBecameReachable(now: Date())
    }

    func handleBackgroundTask(_ task: any BackgroundSyncTaskHandle) async {
        await handleBackgroundTask(task, now: Date())
    }
}
