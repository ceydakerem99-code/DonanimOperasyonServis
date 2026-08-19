import XCTest
@testable import DonanimOperasyonServis

final class SyncLifecycleCoordinatorTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    // MARK: - Foreground / launch

    func testBecomeActiveTriggersSync() async {
        let env = makeEnvironment()
        await env.coordinator.handleBecomeActive(now: now)
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
        let recoveries = await env.recovery.recoverCalls
        XCTAssertEqual(recoveries, 0)
    }

    func testLaunchRecoversThenSyncs() async {
        let env = makeEnvironment()
        await env.coordinator.handleLaunch(now: now)
        let events = await env.sync.events
        XCTAssertEqual(events, ["recover", "syncPending"])
        let recoveries = await env.recovery.recoverCalls
        XCTAssertEqual(recoveries, 1)
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(env.scheduler.scheduleCount, 1)
    }

    func testLaunchAfterBecomeActiveStillRecoversInOrder() async {
        let env = makeEnvironment()
        await env.coordinator.handleBecomeActive(now: now)
        await env.coordinator.handleLaunch(now: now)
        let events = await env.sync.events
        XCTAssertEqual(events, ["syncPending", "recover"])
        let recoveries = await env.recovery.recoverCalls
        XCTAssertEqual(recoveries, 1)
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(env.scheduler.scheduleCount, 1)
    }

    func testDuplicateBecomeActiveDoesNotDrainTwice() async {
        let env = makeEnvironment()
        await env.coordinator.handleLaunch(now: now)
        await env.coordinator.handleBecomeActive(now: now)
        await env.coordinator.handleBecomeActive(now: now)
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
        let recoveries = await env.recovery.recoverCalls
        XCTAssertEqual(recoveries, 1)
    }

    func testOverlappingLifecycleEventsShareOneDrain() async {
        let env = makeEnvironment(delaySync: true)
        let coordinator = env.coordinator
        let timestamp = now
        let launchTask = Task { await coordinator.handleLaunch(now: timestamp) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let activeTask = Task { await coordinator.handleBecomeActive(now: timestamp) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await env.sync.releaseDrain()
        await launchTask.value
        await activeTask.value
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
        let recoveries = await env.recovery.recoverCalls
        XCTAssertEqual(recoveries, 1)
    }

    // MARK: - Offline / online

    func testOfflineForegroundDoesNotCallRemote() async throws {
        let env = try await makeIntegrationEnvironment(online: false)
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-fg-off"),
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)

        await env.coordinator.handleBecomeActive(now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
        XCTAssertEqual(stored.retryCount, 0)
        XCTAssertNil(stored.nextRetryAt)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    func testOnlineForegroundRunsExistingSyncManager() async throws {
        let env = try await makeIntegrationEnvironment(online: true)
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-fg-on"),
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)

        await env.coordinator.handleBecomeActive(now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
    }

    func testNetworkOfflineToOnlineTriggersSync() async {
        let env = makeEnvironment()
        await env.reachability.setReachable(false)
        await env.sync.setOutcome(.deferredOffline)
        await env.coordinator.handleBecomeActive(now: now)
        await env.sync.setOutcome(.completed)
        await env.coordinator.handleNetworkBecameReachable(now: now.addingTimeInterval(5))
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 2)
    }

    func testReachabilityStreamOfflineToOnlineTriggersSync() async {
        let env = makeEnvironment()
        await env.coordinator.startObservingReachability()
        try? await Task.sleep(nanoseconds: 20_000_000)
        await env.reachability.setReachable(false)
        await env.reachability.setReachable(true)

        var calls = 0
        for _ in 0..<40 {
            calls = await env.sync.syncPendingCalls
            if calls >= 1 { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertGreaterThanOrEqual(calls, 1)
    }

    // MARK: - Background

    func testBackgroundTaskCallsSyncManagerAndCompletesSuccess() async {
        let env = makeEnvironment()
        let task = FakeBackgroundSyncTaskHandle()
        await env.coordinator.handleBackgroundTask(task, now: now)
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(task.completedSuccess, true)
        XCTAssertEqual(env.scheduler.scheduleCount, 1)
    }

    func testBackgroundTaskOfflinePreservesQueue() async throws {
        let env = try await makeIntegrationEnvironment(online: false)
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-bg-off"),
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)

        let task = FakeBackgroundSyncTaskHandle()
        await env.coordinator.handleBackgroundTask(task, now: now)

        XCTAssertEqual(task.completedSuccess, true)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
        XCTAssertEqual(stored.retryCount, 0)
        XCTAssertNil(stored.nextRetryAt)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    func testBackgroundTaskFailureDoesNotThrow() async {
        let env = makeEnvironment()
        await env.sync.setError(DomainError.infrastructure(underlying: "boom"))
        let task = FakeBackgroundSyncTaskHandle()
        await env.coordinator.handleBackgroundTask(task, now: now)
        XCTAssertEqual(task.completedSuccess, false)
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
    }

    func testSchedulerRegisterThenRunInvokesCoordinator() async {
        let env = makeEnvironment()
        let scheduler = env.scheduler
        let coordinator = env.coordinator
        let timestamp = now
        scheduler.register { handle in
            await coordinator.handleBackgroundTask(handle, now: timestamp)
        }
        let task = FakeBackgroundSyncTaskHandle()
        await scheduler.run(task)
        let calls = await env.sync.syncPendingCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(task.completedSuccess, true)
        XCTAssertEqual(scheduler.registerCount, 1)
    }

    // MARK: - Idempotency / duplicate remote

    func testOverlappingDrainsDoNotSendTheSameOperationTwice() async throws {
        let env = try await makeIntegrationEnvironment(online: true)
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-once"),
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)

        let coordinator = env.coordinator
        let timestamp = now
        async let first: Void = coordinator.handleBecomeActive(now: timestamp)
        async let second: Void = coordinator.handleBecomeActive(now: timestamp)
        _ = await (first, second)

        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
    }

    // MARK: - Spies

    private struct SpyEnvironment {
        let sync: RecordingSyncManager
        let recovery: RecordingRecoveryHandler
        let reachability: FakeNetworkReachability
        let scheduler: FakeBackgroundSyncScheduler
        let coordinator: SyncLifecycleCoordinator
    }

    private func makeEnvironment(delaySync: Bool = false) -> SpyEnvironment {
        let sync = RecordingSyncManager(delayUntilReleased: delaySync)
        let recovery = RecordingRecoveryHandler(sync: sync)
        let reachability = FakeNetworkReachability()
        let scheduler = FakeBackgroundSyncScheduler()
        let coordinator = SyncLifecycleCoordinator(
            syncManager: sync,
            recovery: recovery,
            reachability: reachability,
            scheduler: scheduler,
            coalescingInterval: 2
        )
        return SpyEnvironment(
            sync: sync,
            recovery: recovery,
            reachability: reachability,
            scheduler: scheduler,
            coordinator: coordinator
        )
    }

    private struct IntegrationEnvironment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let probe: SyncRemoteProbe
        let coordinator: SyncLifecycleCoordinator
    }

    private func makeIntegrationEnvironment(online: Bool) async throws -> IntegrationEnvironment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let reachability = FakeNetworkReachability(isReachable: online)
        let localEntities = SyncEntityRepositories(
            users: local.users,
            customers: local.customers,
            workOrders: local.workOrders,
            notes: local.notes,
            photos: local.photos,
            locations: local.locations,
            statusHistory: local.statusHistory,
            signatures: local.signatures,
            editRequests: local.editRequests,
            notifications: local.notifications
        )
        let manager = LocalToRemoteSyncManager(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: localEntities,
            remote: remote.repositories,
            reachability: reachability
        )
        let coordinator = SyncLifecycleCoordinator(
            syncManager: manager,
            recovery: LocalSyncRecoveryHandler(queue: local.syncOperations),
            reachability: reachability,
            scheduler: FakeBackgroundSyncScheduler()
        )
        return IntegrationEnvironment(
            local: local,
            queue: local.syncOperations,
            probe: probe,
            coordinator: coordinator
        )
    }
}

// MARK: - Test doubles

actor RecordingSyncManager: SyncManaging {
    private(set) var syncPendingCalls = 0
    private(set) var events: [String] = []
    private var outcome: SyncDrainOutcome = .completed
    private var error: Error?
    private var delayUntilReleased: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(delayUntilReleased: Bool = false) {
        self.delayUntilReleased = delayUntilReleased
    }

    func setOutcome(_ outcome: SyncDrainOutcome) {
        self.outcome = outcome
    }

    func setError(_ error: Error?) {
        self.error = error
    }

    func record(_ event: String) {
        events.append(event)
    }

    func releaseDrain() {
        continuation?.resume()
        continuation = nil
        delayUntilReleased = false
    }

    func syncPending(now: Date) async throws -> SyncDrainOutcome {
        syncPendingCalls += 1
        events.append("syncPending")
        if delayUntilReleased {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        if let error { throw error }
        return outcome
    }

    func sync(operation: SyncOperation, now: Date) async throws {}
}

actor RecordingRecoveryHandler: SyncRecoveryHandling {
    private let sync: RecordingSyncManager
    private(set) var recoverCalls = 0

    init(sync: RecordingSyncManager) {
        self.sync = sync
    }

    func recoverInterruptedOperations(now: Date) async throws -> SyncRecoveryOutcome {
        recoverCalls += 1
        await sync.record("recover")
        return SyncRecoveryOutcome(recoveredOperationIDs: [])
    }
}
