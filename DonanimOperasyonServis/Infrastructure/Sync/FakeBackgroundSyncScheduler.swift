import Foundation
import os

/// Deterministic `BackgroundSyncScheduling` for unit tests and
/// `DIContainer.mock()`. Does not talk to `BGTaskScheduler`.
final class FakeBackgroundSyncScheduler: BackgroundSyncScheduling, @unchecked Sendable {

    let configuration: BackgroundSyncConfiguration
    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State: Sendable {
        var registerCount = 0
        var scheduleCount = 0
        var handler: (@Sendable (any BackgroundSyncTaskHandle) async -> Void)?
    }

    init(configuration: BackgroundSyncConfiguration = .appRefresh) {
        self.configuration = configuration
    }

    var registerCount: Int { lock.withLock { $0.registerCount } }
    var scheduleCount: Int { lock.withLock { $0.scheduleCount } }

    func register(
        _ handler: @escaping @Sendable (any BackgroundSyncTaskHandle) async -> Void
    ) {
        lock.withLock { state in
            state.registerCount += 1
            state.handler = handler
        }
    }

    func scheduleNext() {
        lock.withLock { $0.scheduleCount += 1 }
    }

    func run(_ task: any BackgroundSyncTaskHandle) async {
        let handler = lock.withLock { $0.handler }
        await handler?(task)
    }
}

/// Records `complete(success:)` for background-task tests.
final class FakeBackgroundSyncTaskHandle: BackgroundSyncTaskHandle, @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    var completedSuccess: Bool? { lock.withLock { $0 } }

    func complete(success: Bool) {
        lock.withLock { current in
            if current == nil {
                current = success
            }
        }
    }
}
