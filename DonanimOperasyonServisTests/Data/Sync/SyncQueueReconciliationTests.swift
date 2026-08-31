import XCTest
@testable import DonanimOperasyonServis

final class SyncQueueReconciliationTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    // MARK: - Classifier

    func testClassifierMarksFailedStaleWhenNewerSucceededExists() throws {
        let failed = try makeOperation(
            id: "fail-old",
            entityId: "note-1",
            entityType: .workOrderNote,
            localVersion: 1
        )
        var failedRow = failed
        failedRow.status = .failed
        failedRow.errorMessage = SyncError.unauthorized.diagnosticMessage

        let succeeded = try makeOperation(
            id: "ok-new",
            entityId: "note-1",
            entityType: .workOrderNote,
            localVersion: 2,
            createdAt: now.addingTimeInterval(60)
        )
        var succeededRow = succeeded
        succeededRow.status = .succeeded

        let stale = SyncQueueIssueClassifier.staleFailedIDs(
            failed: [failedRow],
            succeeded: [succeededRow]
        )
        XCTAssertEqual(stale, [failedRow.id])
        XCTAssertEqual(SyncQueueIssueClassifier.activeFailedCount([failedRow]), 1)
    }

    func testClassifierMarksChildFailedStaleWhenParentWorkOrderSucceeded() throws {
        let failed = try SyncOperation.pending(
            id: SyncOperationID("child-fail"),
            entityType: .workOrderNote,
            entityId: "note-stale",
            operationType: .create,
            payloadReference: "wo-parent",
            createdAt: now,
            localVersion: 1
        )
        var failedRow = failed
        failedRow.status = .failed
        failedRow.errorMessage = SyncError.unauthorized.diagnosticMessage

        let succeeded = try SyncOperation.pending(
            id: SyncOperationID("wo-ok"),
            entityType: .workOrder,
            entityId: "wo-parent",
            operationType: .create,
            createdAt: now.addingTimeInterval(30),
            localVersion: 1
        )
        var succeededRow = succeeded
        succeededRow.status = .succeeded

        let stale = SyncQueueIssueClassifier.staleFailedIDs(
            failed: [failedRow],
            succeeded: [succeededRow]
        )
        XCTAssertEqual(stale, [failedRow.id])
    }

    func testClassifierKeepsFailedWhenNoNewerSucceeded() throws {
        let failed = try makeOperation(id: "fail-only", entityId: "note-2", localVersion: 1)
        var failedRow = failed
        failedRow.status = .failed
        failedRow.errorMessage = SyncError.unauthorized.diagnosticMessage

        let stale = SyncQueueIssueClassifier.staleFailedIDs(failed: [failedRow], succeeded: [])
        XCTAssertTrue(stale.isEmpty)
        XCTAssertEqual(SyncQueueIssueClassifier.activeFailedCount([failedRow]), 1)
        XCTAssertEqual(SyncQueueIssueClassifier.retryableFailedCount([failedRow]), 0)
    }

    func testClassifierTreatsRetryableFailedAsWaitingNotPermanent() throws {
        let failed = try makeOperation(id: "retry", entityId: "cust-1", entityType: .customer)
        var failedRow = failed
        failedRow.status = .failed
        failedRow.errorMessage = SyncError.networkUnavailable.diagnosticMessage
        failedRow.nextRetryAt = now.addingTimeInterval(8)

        XCTAssertEqual(SyncQueueIssueClassifier.kind(ofFailed: failedRow), .retryable)
        XCTAssertEqual(SyncQueueIssueClassifier.activeFailedCount([failedRow]), 0)
        XCTAssertEqual(SyncQueueIssueClassifier.retryableFailedCount([failedRow]), 1)
    }

    // MARK: - Drain prune

    func testStaleFailedPlusNewerSucceededIsNotActiveError() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer(id: CustomerID("entity-1"))
        try await env.local.customers.save(customer)
        let failed = try await seedFailed(
            id: "stale-fail",
            entityId: "entity-1",
            localVersion: 1,
            error: .unauthorized,
            nextRetryAt: nil,
            queue: env.queue
        )
        _ = try await seedSucceeded(
            id: "later-ok",
            entityId: "entity-1",
            localVersion: 2,
            queue: env.queue
        )

        _ = try await env.manager.syncPending(now: now)

        do {
            _ = try await env.queue.fetch(id: failed.id)
            XCTFail("stale failed row should have been pruned")
        } catch let error as DomainError {
            guard case .notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
        do {
            _ = try await env.queue.fetch(id: SyncOperationID("later-ok"))
            XCTFail("succeeded row should have been pruned")
        } catch let error as DomainError {
            guard case .notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.activeFailedCount, 0)
        XCTAssertEqual(report?.retryableFailedCount, 0)
    }

    func testPermanentFailedWithoutSucceededRemainsActiveError() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer(id: CustomerID("entity-2"))
        try await env.local.customers.save(customer)
        let failed = try await seedFailed(
            id: "real-fail",
            entityId: "entity-2",
            localVersion: 1,
            error: .unauthorized,
            nextRetryAt: nil,
            queue: env.queue
        )

        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: failed.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, SyncError.unauthorized.diagnosticMessage)
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.activeFailedCount, 1)
        XCTAssertEqual(report?.retryableFailedCount, 0)
        XCTAssertEqual(report?.summaryLine, "1 işlem senkronizasyon hatası")
    }

    func testHeldChildIsNotActiveError() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let location = DomainFixtures.location(
            workOrderId: order.id,
            event: .arrived,
            capturedByUserId: tech.id
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await env.local.locations.save(location)

        let operation = try SyncOperation.pending(
            id: SyncOperationID("held-loc"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(operation)
        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.activeFailedCount, 0)
        XCTAssertEqual(report?.retryableFailedCount, 0)
        XCTAssertGreaterThan(report?.held ?? 0, 0)
        XCTAssertEqual(report?.summaryLine, "Senkronize edilecek işlem yok")
    }

    func testRetryableFailedIsWaitingNotActiveError() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "retry-fail",
            entityId: customer.id.rawValue,
            entityType: .customer
        )
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertNotNil(stored.nextRetryAt)
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.activeFailedCount, 0)
        XCTAssertEqual(report?.retryableFailedCount, 1)
        XCTAssertEqual(report?.summaryLine, "1 işlem senkronizasyon için bekliyor")
    }

    func testPermanentFailedFromDrainIsActiveError() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.permissionDenied"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "perm-fail",
            entityId: customer.id.rawValue,
            entityType: .customer
        )
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, SyncError.unauthorized.diagnosticMessage)
        XCTAssertNil(stored.nextRetryAt)
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.activeFailedCount, 1)
        XCTAssertEqual(report?.retryableFailedCount, 0)
    }

    func testSucceededOperationsAreRemovedFromQueueAfterDrain() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "ok-prune",
            entityId: customer.id.rawValue,
            entityType: .customer
        )
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: operation.id))
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.succeeded, 1)
        XCTAssertEqual(report?.activeFailedCount, 0)
        XCTAssertEqual(report?.summaryLine, "1 işlem senkronize edildi")
        let remaining = try await env.queue.list(
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        XCTAssertTrue(remaining.isEmpty)
    }

    func testUnauthorizedIsNotAutomaticallyRetried() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.permissionDenied"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "no-retry",
            entityId: customer.id.rawValue,
            entityType: .customer
        )
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)
        _ = try await env.manager.syncPending(now: now.addingTimeInterval(10_000))

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, 1)
        XCTAssertNil(stored.nextRetryAt)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    func testUnauthorizedChildIsRequeuedWhenRemoteParentExists() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let location = DomainFixtures.location(
            workOrderId: order.id,
            event: .arrived,
            capturedByUserId: tech.id
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await env.local.locations.save(location)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(order, on: env.remoteWorkOrders)

        let failed = try await seedFailed(
            id: "legacy-unauth-child",
            entityId: location.id,
            entityType: .workOrderLocation,
            payloadReference: order.id.rawValue,
            localVersion: 1,
            error: .unauthorized,
            nextRetryAt: nil,
            queue: env.queue
        )

        _ = try await env.manager.syncPending(now: now)

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: failed.id))
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.contains(.save(.workOrderLocation, location.id)))
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.activeFailedCount, 0)
        let snapshot = try await env.manager.issueSnapshot()
        XCTAssertEqual(snapshot.activeFailedCount, 0)
    }

    func testSuccessfulWorkOrderCreateDoesNotIncreaseActiveFailedCount() async throws {
        let env = try await makeEnvironment()
        let operatorUser = DomainFixtures.operatorUser()
        let order = DomainFixtures.workOrder(createdByUserId: operatorUser.id)
        try await env.local.users.save(operatorUser)
        try await env.local.workOrders.save(order)
        env.auth.setUID(operatorUser.id.rawValue)

        _ = try await env.manager.syncPending(now: now)
        let before = try await env.manager.issueSnapshot()
        XCTAssertEqual(before.activeFailedCount, 0)

        let create = try SyncOperation.pending(
            id: SyncOperationID("wo-create-ok"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1,
            actorUserId: operatorUser.id.rawValue
        )
        _ = try await env.queue.enqueue(create)
        _ = try await env.manager.syncPending(now: now.addingTimeInterval(1))

        let after = try await env.manager.issueSnapshot()
        XCTAssertEqual(after.activeFailedCount, 0)
        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.activeFailedCount, 0)
        XCTAssertEqual(report?.succeeded, 1)
    }

    func testPendingWorkOrderWithoutActorUserIdSyncsAfterBackfill() async throws {
        let env = try await makeEnvironment()
        let operatorUser = DomainFixtures.operatorUser()
        let order = DomainFixtures.workOrder(createdByUserId: operatorUser.id)
        try await env.local.users.save(operatorUser)
        try await env.local.workOrders.save(order)
        env.auth.setUID(operatorUser.id.rawValue)

        let create = try SyncOperation.pending(
            id: SyncOperationID("legacy-wo-no-actor"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(create)

        _ = try await env.manager.syncPending(now: now)

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: create.id))
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.contains(.save(.workOrder, order.id.rawValue)))
    }

    func testFailedCreatePrunedWhenRemoteEntityAlreadyExists() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer(id: CustomerID("remote-exists"))
        try await env.local.customers.save(customer)
        try await env.remoteCustomers.save(customer)

        let failed = try await seedFailed(
            id: "dup-create",
            entityId: customer.id.rawValue,
            localVersion: 1,
            error: .unauthorized,
            nextRetryAt: nil,
            queue: env.queue
        )

        _ = try await env.manager.syncPending(now: now)

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: failed.id))
        let snapshot = try await env.manager.issueSnapshot()
        XCTAssertEqual(snapshot.activeFailedCount, 0)
    }

    func testIssueSnapshotWaitingIncludesPendingHeldOperations() throws {
        var pendingWO = try SyncOperation.pending(
            id: SyncOperationID("held-wo"),
            entityType: .workOrder,
            entityId: "wo-1",
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        pendingWO.status = .pending

        var retryFailed = try SyncOperation.pending(
            id: SyncOperationID("retry-fail"),
            entityType: .customer,
            entityId: "cust-1",
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        retryFailed.status = .failed
        retryFailed.nextRetryAt = now.addingTimeInterval(60)

        let snapshot = SyncQueueIssueClassifier.snapshot(
            failed: [retryFailed],
            pending: [pendingWO],
            succeeded: [],
            conflicts: []
        )
        XCTAssertEqual(snapshot.pendingCount, 1)
        XCTAssertEqual(snapshot.retryableFailedCount, 1)
        XCTAssertEqual(snapshot.retryableFailedCount + snapshot.pendingCount, 2)
    }

    func testProgressStoreReplacesStaleBadgeSnapshot() {
        let store = SyncProgressStore()
        let stale = SyncDrainReport(
            startedAt: now,
            finishedAt: now,
            pendingAtStart: 67,
            succeeded: 0,
            failed: 67,
            retried: 0,
            held: 0,
            conflicts: 0,
            operations: [],
            deferredOffline: false,
            activeFailedCount: 67,
            retryableFailedCount: 0
        )
        store.finish(report: stale)
        XCTAssertEqual(store.issueSnapshot?.activeFailedCount, 67)
        XCTAssertEqual(store.lastReport?.activeFailedCount, 67)

        let fresh = SyncDrainReport(
            startedAt: now.addingTimeInterval(10),
            finishedAt: now.addingTimeInterval(11),
            pendingAtStart: 1,
            succeeded: 1,
            failed: 0,
            retried: 0,
            held: 0,
            conflicts: 0,
            operations: [],
            deferredOffline: false,
            activeFailedCount: 0,
            retryableFailedCount: 0
        )
        store.finish(report: fresh, snapshot: .empty(at: now.addingTimeInterval(11)))
        XCTAssertEqual(store.issueSnapshot?.activeFailedCount, 0)
        XCTAssertEqual(store.lastReport?.activeFailedCount, 0)
        XCTAssertEqual(store.lastReport?.succeeded, 1)
    }

    // MARK: - Helpers

    private func seedFailed(
        id: String,
        entityId: String,
        entityType: SyncEntityType = .customer,
        payloadReference: String? = nil,
        localVersion: Int,
        error: SyncError,
        nextRetryAt: Date?,
        queue: SwiftDataSyncOperationRepository
    ) async throws -> SyncOperation {
        let pending = try makeOperation(
            id: id,
            entityId: entityId,
            entityType: entityType,
            localVersion: localVersion,
            payloadReference: payloadReference
        )
        _ = try await queue.enqueue(pending)
        var current = try await queue.fetch(id: pending.id)
        current.status = .inProgress
        current.updatedAt = now
        try await queue.update(current)
        current = try await queue.fetch(id: pending.id)
        current.status = .failed
        current.errorMessage = error.diagnosticMessage
        current.nextRetryAt = nextRetryAt
        current.retryCount = 1
        current.lastAttemptAt = now
        current.updatedAt = now
        try await queue.update(current)
        return try await queue.fetch(id: pending.id)
    }

    private func seedSucceeded(
        id: String,
        entityId: String,
        localVersion: Int,
        queue: SwiftDataSyncOperationRepository
    ) async throws -> SyncOperation {
        let pending = try makeOperation(
            id: id,
            entityId: entityId,
            localVersion: localVersion,
            createdAt: now.addingTimeInterval(TimeInterval(localVersion))
        )
        _ = try await queue.enqueue(pending)
        var current = try await queue.fetch(id: pending.id)
        current.status = .inProgress
        current.updatedAt = now
        try await queue.update(current)
        current = try await queue.fetch(id: pending.id)
        current.status = .succeeded
        current.updatedAt = now
        try await queue.update(current)
        return try await queue.fetch(id: pending.id)
    }

    private func makeOperation(
        id: String,
        entityId: String,
        entityType: SyncEntityType = .customer,
        localVersion: Int = 1,
        createdAt: Date? = nil,
        payloadReference: String? = nil
    ) throws -> SyncOperation {
        let payload: String?
        if let payloadReference {
            payload = payloadReference
        } else if entityType == .workOrderNote {
            payload = "parent"
        } else {
            payload = nil
        }
        return try SyncOperation.pending(
            id: SyncOperationID(id),
            entityType: entityType,
            entityId: entityId,
            operationType: .create,
            payloadReference: payload,
            createdAt: createdAt ?? now,
            localVersion: localVersion
        )
    }

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let probe: SyncRemoteProbe
        let manager: LocalToRemoteSyncManager
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let remoteCustomers: InMemoryCustomerRepository
        let auth: FakeFirebaseAuthService
    }

    private func makeEnvironment() async throws -> Environment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
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
            reachability: FakeNetworkReachability(),
            authService: auth
        )
        return Environment(
            local: local,
            queue: local.syncOperations,
            probe: probe,
            manager: manager,
            remoteWorkOrders: remote.workOrders,
            remoteCustomers: remote.customers,
            auth: auth
        )
    }
}
