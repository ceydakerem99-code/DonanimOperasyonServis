import Foundation
import BackgroundTasks
import os

/// Production `BackgroundSyncScheduling` wrapping `BGTaskScheduler`.
///
/// Registers a `BGAppRefreshTask` (time-limited). The handler must
/// call only `SyncLifecycleCoordinator` / `SyncManaging` — never a
/// SwiftData `ModelContext`.
final class SystemBackgroundSyncScheduler: BackgroundSyncScheduling, @unchecked Sendable {

    let configuration: BackgroundSyncConfiguration

    init(configuration: BackgroundSyncConfiguration = .appRefresh) {
        self.configuration = configuration
    }

    func register(
        _ handler: @escaping @Sendable (any BackgroundSyncTaskHandle) async -> Void
    ) {
        let identifier = configuration.taskIdentifier
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let handle = SystemBackgroundSyncTaskHandle(task: refresh)
            refresh.expirationHandler = {
                handle.complete(success: false)
            }
            Task {
                await handler(handle)
            }
        }
        if !registered {
            AppLogger.sync.error(
                "BGTaskScheduler.register failed for \(identifier, privacy: .public)"
            )
        }
    }

    func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: configuration.taskIdentifier)
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: configuration.earliestBeginDelay
        )
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.sync.error(
                "BGTaskScheduler.submit failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// Ensures `setTaskCompleted` is invoked at most once.
final class SystemBackgroundSyncTaskHandle: BackgroundSyncTaskHandle, @unchecked Sendable {

    private let task: BGAppRefreshTask
    private let completed = OSAllocatedUnfairLock(initialState: false)

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func complete(success: Bool) {
        let already = completed.withLock { done -> Bool in
            if done { return true }
            done = true
            return false
        }
        guard !already else { return }
        task.setTaskCompleted(success: success)
    }
}
