import XCTest
@testable import DonanimOperasyonServis

final class NetworkRetryRecoveryTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    // MARK: - Network

    func testOfflineSyncPendingDoesNotCallRemoteAndKeepsPendingMetadata() async throws {
        let env = try await makeEnvironment(online: false)
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-off", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        let outcome = try await env.manager.syncPending(now: now)
        XCTAssertEqual(outcome, .deferredOffline)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
        XCTAssertEqual(stored.retryCount, 0)
        XCTAssertNil(stored.nextRetryAt)
        XCTAssertNil(stored.errorMessage)
        XCTAssertNil(stored.lastAttemptAt)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        let local = try await env.local.customers.fetch(id: customer.id)
        XCTAssertEqual(local, customer)
    }

    func testOnlineSyncPendingRunsNormally() async throws {
        let env = try await makeEnvironment(online: true)
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-on", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        let outcome = try await env.manager.syncPending(now: now)
        XCTAssertEqual(outcome, .completed)
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: operation.id))
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
    }

    func testOfflineThenOnlineDrain() async throws {
        let env = try await makeEnvironment(online: false)
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-flip", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        let flippedOffline = try await env.manager.syncPending(now: now)
        XCTAssertEqual(flippedOffline, .deferredOffline)
        await env.reachability.setReachable(true)
        let flippedOnline = try await env.manager.syncPending(now: now)
        XCTAssertEqual(flippedOnline, .completed)
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: operation.id))
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
    }

    func testFakeReachabilityCanFlipDeterministically() async {
        let fake = FakeNetworkReachability(isReachable: true)
        let initiallyOnline = await fake.isReachable
        XCTAssertTrue(initiallyOnline)
        await fake.setReachable(false)
        let offline = await fake.isReachable
        XCTAssertFalse(offline)
        await fake.setReachable(true)
        let onlineAgain = await fake.isReachable
        XCTAssertTrue(onlineAgain)
    }

    // MARK: - Retryable errors

    func testRemoteNetworkUnavailableUpdatesRetryMetadata() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-net", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        let drain = try await env.manager.syncPending(now: now)
        XCTAssertEqual(drain, .completed)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, 1)
        XCTAssertEqual(stored.errorMessage, "networkUnavailable")
        XCTAssertEqual(stored.lastAttemptAt, now)
        XCTAssertEqual(
            stored.nextRetryAt,
            SyncRetryPolicy.nextRetryDate(error: .networkUnavailable, retryCount: 0, now: now)
        )
        let local = try await env.local.customers.fetch(id: customer.id)
        XCTAssertEqual(local, customer)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    func testServerErrorUpdatesRetryMetadata() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.serverError"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-5xx", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, 1)
        XCTAssertEqual(stored.errorMessage, "serverError")
        XCTAssertEqual(
            stored.nextRetryAt,
            SyncRetryPolicy.nextRetryDate(error: .serverError, retryCount: 0, now: now)
        )
    }

    func testRetryCountIncrementsOnEachRemoteAttempt() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-inc", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)
        let first = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(first.retryCount, 1)
        let retryAt = try XCTUnwrap(first.nextRetryAt)

        _ = try await env.manager.syncPending(now: retryAt)
        let second = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(second.retryCount, 2)
        XCTAssertEqual(
            second.nextRetryAt,
            SyncRetryPolicy.nextRetryDate(error: .networkUnavailable, retryCount: 1, now: retryAt)
        )
    }

    func testFutureNextRetryAtIsNotSelectedUntilDue() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-wait", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)
        let failed = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(failed.retryCount, 1)
        let due = try XCTUnwrap(failed.nextRetryAt)

        _ = try await env.manager.syncPending(now: now.addingTimeInterval(1))
        let stillWaiting = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stillWaiting.retryCount, 1)
        XCTAssertEqual(stillWaiting.nextRetryAt, due)

        await env.probe.setError(nil)
        _ = try await env.manager.syncPending(now: due)
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: operation.id))
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
    }

    func testMaxRetryStopsAutomaticSelection() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-cap", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        var clock = now
        for _ in 0..<(SyncRetryPolicy.maximumRetryCount + 1) {
            _ = try await env.manager.syncPending(now: clock)
            let stored = try await env.queue.fetch(id: operation.id)
            clock = stored.nextRetryAt ?? clock.addingTimeInterval(1)
        }

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, SyncRetryPolicy.maximumRetryCount + 1)
        XCTAssertNil(stored.nextRetryAt)
        let pendingAfterCap = try await env.queue.fetchPending(now: clock.addingTimeInterval(10_000))
        XCTAssertTrue(pendingAfterCap.isEmpty)
        _ = try await env.manager.syncPending(now: clock.addingTimeInterval(10_000))
        let again = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(again.retryCount, stored.retryCount)
        XCTAssertEqual(again.status, .failed)
    }

    // MARK: - Non-retryable

    func testUnauthorizedFailsWithoutRetrySchedule() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.permissionDenied"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-401", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, "unauthorized")
        XCTAssertNil(stored.nextRetryAt)
        let pendingUnauthorized = try await env.queue.fetchPending(now: now.addingTimeInterval(10_000))
        XCTAssertTrue(pendingUnauthorized.isEmpty)
    }

    func testInvalidPayloadFailsWithoutRetrySchedule() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.invalidData(reason: "shape"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(id: "op-bad", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, "invalidPayload")
        XCTAssertNil(stored.nextRetryAt)
    }

    func testNotFoundFailsAccordingToRetryPolicy() async throws {
        let env = try await makeEnvironment()
        let operation = try makeOperation(id: "op-404", entityId: "ghost")
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, "notFound")
        XCTAssertFalse(SyncRetryPolicy.isRetryable(.notFound))
        XCTAssertNil(stored.nextRetryAt)
        let pendingNotFound = try await env.queue.fetchPending(now: now.addingTimeInterval(10_000))
        XCTAssertTrue(pendingNotFound.isEmpty)
    }

    // MARK: - Conflict

    func testConflictIsNotRetried() async throws {
        let env = try await makeEnvironment()
        let localOrder = DomainFixtures.workOrder(status: .inProgress)
        try await env.local.workOrders.save(localOrder)
        try await env.remoteWorkOrders.save(
            DomainFixtures.workOrder(status: .completed, completedAt: now)
        )
        let operation = try makeOperation(
            id: "op-cf",
            entityType: .workOrder,
            entityId: localOrder.id.rawValue,
            operationType: .update
        )
        _ = try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let conflicted = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(conflicted.status, .conflict)
        let retryCount = conflicted.retryCount

        _ = try await env.manager.syncPending(now: now.addingTimeInterval(60))
        let again = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(again.status, .conflict)
        XCTAssertEqual(again.retryCount, retryCount)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        let conflict = try await env.conflicts.fetch(syncOperationId: operation.id)
        XCTAssertEqual(conflict?.status, .unresolved)
        XCTAssertNil(conflict?.resolution)
    }

    func testUnresolvedConflictHoldSurvivesOnlineDrain() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer(name: "Yerel")
        try await env.local.customers.save(customer)
        try await env.remoteCustomers.save(DomainFixtures.customer(name: "Sunucu"))
        let operation = try makeOperation(id: "op-hold", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)
        try await env.conflicts.save(
            SyncConflict.unresolved(
                id: SyncConflictID("cf-hold"),
                syncOperationId: operation.id,
                entityType: .customer,
                entityId: customer.id.rawValue,
                localVersion: 1,
                remoteVersion: 2,
                detectedAt: now
            )
        )

        _ = try await env.manager.syncPending(now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
        XCTAssertEqual(stored.retryCount, 0)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        let stillLocal = try await env.local.customers.fetch(id: customer.id)
        XCTAssertEqual(stillLocal.name, "Yerel")
        let open = try await env.conflicts.fetch(id: SyncConflictID("cf-hold"))
        XCTAssertNil(open.resolution)
    }

    // MARK: - Recovery

    func testRecoveryFindsInProgressWithoutMarkingSucceededOrDuplicating() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        var operation = try makeOperation(id: "op-rec", entityId: customer.id.rawValue)
        _ = try await env.queue.enqueue(operation)
        operation.status = .inProgress
        operation.updatedAt = now
        try await env.queue.update(operation)

        let found = try await env.queue.fetchInProgress()
        XCTAssertEqual(found.map(\.id), [operation.id])

        let outcome = try await env.recovery.recoverInterruptedOperations(now: now)
        XCTAssertEqual(outcome.recoveredOperationIDs, [operation.id])

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertNotEqual(stored.status, .succeeded)
        XCTAssertEqual(stored.id, operation.id)
        XCTAssertEqual(stored.idempotencyKey, operation.idempotencyKey)
        XCTAssertEqual(stored.retryCount, 1)
        XCTAssertEqual(stored.errorMessage, "networkUnavailable")
        XCTAssertEqual(
            stored.nextRetryAt,
            SyncRetryPolicy.nextRetryDate(error: .networkUnavailable, retryCount: 0, now: now)
        )

        let listed = try await env.queue.list(entityType: .customer, entityId: customer.id.rawValue)
        XCTAssertEqual(listed.count, 1)
        let stillInProgress = try await env.queue.fetchInProgress()
        XCTAssertTrue(stillInProgress.isEmpty)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        let local = try await env.local.customers.fetch(id: customer.id)
        XCTAssertEqual(local, customer)
    }

    func testRecoveryThenManualSyncUsesSameIdempotencyKey() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        var operation = try makeOperation(id: "op-rec2", entityId: customer.id.rawValue)
        let originalKey = operation.idempotencyKey
        _ = try await env.queue.enqueue(operation)
        operation.status = .inProgress
        operation.updatedAt = now
        try await env.queue.update(operation)

        _ = try await env.recovery.recoverInterruptedOperations(now: now)
        let recovered = try await env.queue.fetch(id: operation.id)
        let due = try XCTUnwrap(recovered.nextRetryAt)

        XCTAssertEqual(recovered.idempotencyKey, originalKey)
        _ = try await env.manager.syncPending(now: due)
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: operation.id))
        let listed = try await env.queue.list(entityType: .customer, entityId: customer.id.rawValue)
        XCTAssertTrue(listed.isEmpty)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
    }

    // MARK: - FIFO / integration

    func testOfflineOnlinePreservesFIFO() async throws {
        let env = try await makeEnvironment(online: false)
        let first = DomainFixtures.customer(id: CustomerID("c-a"), name: "A")
        let second = DomainFixtures.customer(id: CustomerID("c-b"), name: "B")
        try await env.local.customers.save(first)
        try await env.local.customers.save(second)
        let later = try makeOperation(
            id: "z-later",
            entityId: second.id.rawValue,
            createdAt: now.addingTimeInterval(10)
        )
        let early = try makeOperation(
            id: "a-early",
            entityId: first.id.rawValue,
            createdAt: now
        )
        _ = try await env.queue.enqueue(later)
        _ = try await env.queue.enqueue(early)

        let deferred = try await env.manager.syncPending(now: now.addingTimeInterval(10))
        XCTAssertEqual(deferred, .deferredOffline)
        let writesWhileOffline = await env.probe.recordedWrites()
        XCTAssertTrue(writesWhileOffline.isEmpty)

        await env.reachability.setReachable(true)
        let completed = try await env.manager.syncPending(now: now.addingTimeInterval(10))
        XCTAssertEqual(completed, .completed)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(
            writes,
            [.save(.customer, first.id.rawValue), .save(.customer, second.id.rawValue)]
        )
    }

    // MARK: - Environment

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let conflicts: SwiftDataSyncConflictRepository
        let probe: SyncRemoteProbe
        let reachability: FakeNetworkReachability
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let remoteCustomers: InMemoryCustomerRepository
        let manager: LocalToRemoteSyncManager
        let recovery: LocalSyncRecoveryHandler
    }

    private func makeEnvironment(online: Bool = true) async throws -> Environment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let reachability = FakeNetworkReachability(isReachable: online)
        let auth = FakeFirebaseAuthService()
        auth.setUID(DomainFixtures.technicianUser().id.rawValue)
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
            customerSatisfactions: local.customerSatisfactions,
            notifications: local.notifications
        )
        let manager = LocalToRemoteSyncManager(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: localEntities,
            remote: remote.repositories,
            reachability: reachability,
            authService: auth
        )
        return Environment(
            local: local,
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            probe: probe,
            reachability: reachability,
            remoteWorkOrders: remote.workOrders,
            remoteCustomers: remote.customers,
            manager: manager,
            recovery: LocalSyncRecoveryHandler(queue: local.syncOperations)
        )
    }

    private func makeOperation(
        id: String,
        entityType: SyncEntityType = .customer,
        entityId: String,
        operationType: SyncOperationType = .create,
        createdAt: Date? = nil
    ) throws -> SyncOperation {
        try SyncOperation.pending(
            id: SyncOperationID(id),
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            createdAt: createdAt ?? now,
            localVersion: 1
        )
    }
}
