import XCTest
@testable import DonanimOperasyonServis

final class LocalToRemoteSyncManagerTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    // MARK: - Success lifecycle

    func testPendingCreateBecomesSucceededAndWritesRemote() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-cust",
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create
        )
        try await env.queue.enqueue(operation)

        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
        XCTAssertNil(stored.errorMessage)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
        let localStill = try await env.local.customers.fetch(id: customer.id)
        XCTAssertEqual(localStill, customer)
    }

    func testSuccessfulSyncDoesNotOverwriteLocalWithRemoteMutation() async throws {
        let env = try await makeEnvironment()
        await env.remoteCustomers.setTransformOnSave { customer in
            var copy = customer
            copy.name = "SERVER-NAME"
            return copy
        }
        let customer = DomainFixtures.customer(name: "Local Name")
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-no-merge",
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .update
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let local = try await env.local.customers.fetch(id: customer.id)
        XCTAssertEqual(local.name, "Local Name")
        let remote = await env.remoteCustomers.snapshot(customer.id)
        XCTAssertEqual(remote?.name, "SERVER-NAME")
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
    }

    // MARK: - Errors / retry

    func testNetworkErrorFailsWithRetryMetadata() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-net",
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        try await env.queue.enqueue(operation)

        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, 1)
        XCTAssertEqual(stored.errorMessage, "networkUnavailable")
        XCTAssertEqual(stored.lastAttemptAt, now)
        XCTAssertEqual(stored.nextRetryAt, now.addingTimeInterval(2))
        let pendingNow = try await env.queue.fetchPending(now: now)
        XCTAssertTrue(pendingNow.isEmpty)
        let pendingLater = try await env.queue.fetchPending(now: now.addingTimeInterval(2))
        XCTAssertEqual(pendingLater.map(\.id), [operation.id])
    }

    func testMaxRetryStopsSelection() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-max",
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        try await env.queue.enqueue(operation)

        var clock = now
        for _ in 0..<6 {
            try await env.manager.syncPending(now: clock)
            let stored = try await env.queue.fetch(id: operation.id)
            clock = stored.nextRetryAt ?? clock.addingTimeInterval(1)
        }

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, 6)
        XCTAssertNil(stored.nextRetryAt)
        let pending = try await env.queue.fetchPending(now: clock.addingTimeInterval(10_000))
        XCTAssertTrue(pending.isEmpty)
    }

    func testNonRetryableDoesNotScheduleRetry() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.permissionDenied"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-auth",
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, 1)
        XCTAssertEqual(stored.errorMessage, "unauthorized")
        XCTAssertNil(stored.nextRetryAt)
        let pending = try await env.queue.fetchPending(now: now.addingTimeInterval(10_000))
        XCTAssertTrue(pending.isEmpty)
    }

    func testInvalidDataIsFailedNotSucceeded() async throws {
        let env = try await makeEnvironment()
        await env.probe.setError(.invalidData(reason: "shape"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-invalid",
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, "invalidPayload")
        XCTAssertNil(stored.nextRetryAt)
    }

    func testLocalEntityMissingIsFailedNotSucceeded() async throws {
        let env = try await makeEnvironment()
        let operation = try makeOperation(
            id: "op-missing",
            entityType: .customer,
            entityId: "ghost"
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, "notFound")
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    // MARK: - Conflict / completed work order

    func testCompletedRemoteVersusLocalInProgressIsConflict() async throws {
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
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .conflict)
        XCTAssertEqual(stored.errorMessage, "conflict")
        XCTAssertNil(stored.nextRetryAt)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)

        let local = try await env.local.workOrders.fetch(id: localOrder.id)
        XCTAssertEqual(local.status, .inProgress)

        let conflict = try await env.conflicts.fetch(syncOperationId: operation.id)
        XCTAssertEqual(conflict?.entityType, .workOrder)
        XCTAssertEqual(conflict?.status, .unresolved)
        XCTAssertEqual(conflict?.localVersion, 1)
        XCTAssertEqual(conflict?.remoteVersion, 0)
    }

    func testStaleCompletedLocalUpdateIsConflictAndDoesNotReopen() async throws {
        let env = try await makeEnvironment()
        let localOrder = DomainFixtures.workOrder(status: .completed, completedAt: now)
        try await env.local.workOrders.save(localOrder)
        let operation = try makeOperation(
            id: "op-stale",
            entityType: .workOrder,
            entityId: localOrder.id.rawValue,
            operationType: .update
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .conflict)
        let local = try await env.local.workOrders.fetch(id: localOrder.id)
        XCTAssertEqual(local.status, .completed)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    // MARK: - Dispatch

    func testDispatchCoversEachEntityType() async throws {
        let env = try await makeEnvironment()
        let user = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder()
        let note = DomainFixtures.note()
        let photo = DomainFixtures.photo(category: .before)
        let location = DomainFixtures.location(event: .arrived)
        let history = DomainFixtures.statusHistory()
        let signature = DomainFixtures.signature(kind: .technician)
        let edit = DomainFixtures.editRequest()
        let notification = DomainFixtures.notification()

        try await env.local.users.save(user)
        try await env.local.customers.save(customer)
        try await env.local.workOrders.save(order)
        try await env.local.notes.save(note)
        try await env.local.photos.save(photo)
        try await env.local.locations.save(location)
        try await env.local.statusHistory.append(history)
        try await env.local.signatures.save(signature)
        try await env.local.editRequests.save(edit)
        try await env.local.notifications.save(notification)

        let parent = order.id.rawValue
        let ops: [SyncOperation] = try [
            makeOperation(id: "d-user", entityType: .user, entityId: user.id.rawValue),
            makeOperation(id: "d-cust", entityType: .customer, entityId: customer.id.rawValue),
            makeOperation(id: "d-wo", entityType: .workOrder, entityId: order.id.rawValue),
            makeOperation(
                id: "d-note", entityType: .workOrderNote, entityId: note.id,
                payloadReference: parent
            ),
            makeOperation(
                id: "d-photo", entityType: .workOrderPhoto, entityId: photo.id,
                payloadReference: parent
            ),
            makeOperation(
                id: "d-loc", entityType: .workOrderLocation, entityId: location.id,
                payloadReference: parent
            ),
            makeOperation(
                id: "d-hist", entityType: .workOrderStatusHistory, entityId: history.id,
                payloadReference: parent
            ),
            makeOperation(
                id: "d-sig", entityType: .signature, entityId: signature.id,
                payloadReference: parent
            ),
            makeOperation(id: "d-edit", entityType: .editRequest, entityId: edit.id.rawValue),
            makeOperation(
                id: "d-notif", entityType: .notification, entityId: notification.id.rawValue,
                payloadReference: notification.recipientUserId.rawValue
            )
        ]
        for op in ops { try await env.queue.enqueue(op) }
        try await env.manager.syncPending(now: now)

        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.contains(.save(.user, user.id.rawValue)))
        XCTAssertTrue(writes.contains(.save(.customer, customer.id.rawValue)))
        XCTAssertTrue(writes.contains(.save(.workOrder, order.id.rawValue)))
        XCTAssertTrue(writes.contains(.save(.workOrderNote, note.id)))
        XCTAssertTrue(writes.contains(.save(.workOrderPhoto, photo.id)))
        XCTAssertTrue(writes.contains(.save(.workOrderLocation, location.id)))
        XCTAssertTrue(writes.contains(.append(.workOrderStatusHistory, history.id)))
        XCTAssertTrue(writes.contains(.save(.signature, signature.id)))
        XCTAssertTrue(writes.contains(.save(.editRequest, edit.id.rawValue)))
        XCTAssertTrue(writes.contains(.save(.notification, notification.id.rawValue)))
        for op in ops {
            let stored = try await env.queue.fetch(id: op.id)
            XCTAssertEqual(stored.status, .succeeded, op.id.rawValue)
        }
    }

    func testDeleteDispatchIsIdempotentWhenLocalMissing() async throws {
        let env = try await makeEnvironment()
        let operation = try makeOperation(
            id: "op-del",
            entityType: .customer,
            entityId: "already-gone",
            operationType: .delete
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.delete(.customer, "already-gone")])
    }

    func testNoteDeleteDispatch() async throws {
        let env = try await makeEnvironment()
        let order = DomainFixtures.workOrder()
        try await env.local.workOrders.save(order)
        let operation = try makeOperation(
            id: "op-ndel",
            entityType: .workOrderNote,
            entityId: "note-gone",
            operationType: .delete,
            payloadReference: order.id.rawValue
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.delete(.workOrderNote, "note-gone")])
    }

    // MARK: - FIFO / sequential / duplicate

    func testSyncPendingIsFIFOAndSequential() async throws {
        let env = try await makeEnvironment()
        let first = DomainFixtures.customer(id: CustomerID("c-a"), name: "A")
        let second = DomainFixtures.customer(id: CustomerID("c-b"), name: "B")
        try await env.local.customers.save(first)
        try await env.local.customers.save(second)
        let later = try makeOperation(
            id: "z-later",
            entityType: .customer,
            entityId: second.id.rawValue,
            createdAt: now.addingTimeInterval(10)
        )
        let early = try makeOperation(
            id: "a-early",
            entityType: .customer,
            entityId: first.id.rawValue,
            createdAt: now
        )
        try await env.queue.enqueue(later)
        try await env.queue.enqueue(early)
        try await env.manager.syncPending(now: now.addingTimeInterval(10))

        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(
            writes,
            [.save(.customer, first.id.rawValue), .save(.customer, second.id.rawValue)]
        )
        let earlyStored = try await env.queue.fetch(id: early.id)
        let laterStored = try await env.queue.fetch(id: later.id)
        XCTAssertEqual(earlyStored.status, .succeeded)
        XCTAssertEqual(laterStored.status, .succeeded)
    }

    func testDuplicateSyncDoesNotHitRemoteTwice() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-once",
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)
        try await env.manager.sync(operation: operation, now: now.addingTimeInterval(1))
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes.count, 1)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
    }

    func testInProgressOperationIsNotExecutedAgain() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        var operation = try makeOperation(
            id: "op-prog",
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        try await env.queue.enqueue(operation)
        operation.status = .inProgress
        operation.updatedAt = now
        try await env.queue.update(operation)

        try await env.manager.sync(operation: operation, now: now)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .inProgress)
    }

    func testConcurrentSyncOfSameOperationHitsRemoteOnce() async throws {
        let env = try await makeEnvironment()
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try makeOperation(
            id: "op-race",
            entityType: .customer,
            entityId: customer.id.rawValue
        )
        try await env.queue.enqueue(operation)

        let manager = env.manager
        let timestamp = now
        async let first = manager.sync(operation: operation, now: timestamp)
        async let second = manager.sync(operation: operation, now: timestamp)
        try await first
        try await second

        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes.count, 1)
        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
    }

    // MARK: - Environment

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let conflicts: SwiftDataSyncConflictRepository
        let probe: SyncRemoteProbe
        let remoteCustomers: InMemoryCustomerRepository
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let manager: LocalToRemoteSyncManager
    }

    private func makeEnvironment() async throws -> Environment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
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
            remote: remote.repositories
        )
        return Environment(
            local: local,
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            probe: probe,
            remoteCustomers: remote.customers,
            remoteWorkOrders: remote.workOrders,
            manager: manager
        )
    }

    private func makeOperation(
        id: String,
        entityType: SyncEntityType,
        entityId: String,
        operationType: SyncOperationType = .create,
        payloadReference: String? = nil,
        createdAt: Date? = nil
    ) throws -> SyncOperation {
        try SyncOperation.pending(
            id: SyncOperationID(id),
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payloadReference: payloadReference,
            createdAt: createdAt ?? now,
            localVersion: 1
        )
    }
}
