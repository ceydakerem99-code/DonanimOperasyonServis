import XCTest
@testable import DonanimOperasyonServis

final class RemoteToLocalReconciliationEngineTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    func testSameLocalAndRemoteIsNoChangeAndDoesNotRewrite() async throws {
        let env = try makeEnvironment()
        let customer = DomainFixtures.customer(name: "Aynı")
        try await env.local.customers.save(customer)
        try await env.remoteCustomers.save(customer)

        let outcome = try await env.engine.reconcile(
            request(entityId: customer.id.rawValue, versions: v(1, 1, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .noChange)
        let stored = try await env.local.customers.fetch(id: customer.id)
        XCTAssertEqual(stored, customer)
    }

    func testRemoteChangedLocalUnchangedAppliesDomainEntity() async throws {
        let env = try makeEnvironment()
        let local = DomainFixtures.customer(name: "Yerel")
        var remote = local
        remote.name = "Sunucu"
        remote.updatedAt = now.addingTimeInterval(60)
        try await env.local.customers.save(local)
        try await env.remoteCustomers.save(remote)

        let outcome = try await env.engine.reconcile(
            request(entityId: local.id.rawValue, versions: v(1, 2, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .applyRemote)
        let stored = try await env.local.customers.fetch(id: local.id)
        XCTAssertEqual(stored.name, "Sunucu")
        XCTAssertEqual(stored, remote)
    }

    func testPendingLocalUpdateAndOldRemoteKeepsLocalAndQueue() async throws {
        let env = try makeEnvironment()
        var local = DomainFixtures.customer(name: "Yerel-yeni")
        let remote = DomainFixtures.customer(name: "Eski-sunucu")
        try await env.local.customers.save(local)
        try await env.remoteCustomers.save(remote)
        let operation = try pendingUpdate(entityId: local.id.rawValue, localVersion: 2, remoteVersion: 1)
        try await env.queue.enqueue(operation)

        let outcome = try await env.engine.reconcile(
            request(entityId: local.id.rawValue, versions: v(2, 1, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .keepLocal)
        local = try await env.local.customers.fetch(id: local.id)
        XCTAssertEqual(local.name, "Yerel-yeni")
        let queued = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(queued.status, .pending)
        XCTAssertEqual(queued.idempotencyKey, operation.idempotencyKey)
    }

    func testPendingLocalUpdateAndRemoteChangedPersistsConflictWithoutDeletingQueue() async throws {
        let env = try makeEnvironment()
        let local = DomainFixtures.customer(name: "Yerel-yeni")
        var remote = DomainFixtures.customer(name: "Sunucu-yeni")
        remote.updatedAt = now.addingTimeInterval(90)
        try await env.local.customers.save(local)
        try await env.remoteCustomers.save(remote)
        let operation = try pendingUpdate(entityId: local.id.rawValue, localVersion: 2, remoteVersion: 1)
        try await env.queue.enqueue(operation)

        let outcome = try await env.engine.reconcile(
            request(entityId: local.id.rawValue, versions: v(2, 4, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .conflict)
        XCTAssertEqual(outcome.persistedConflict?.status, .unresolved)
        XCTAssertEqual(outcome.persistedConflict?.entityId, local.id.rawValue)
        XCTAssertEqual(outcome.persistedConflict?.localVersion, 2)
        XCTAssertEqual(outcome.persistedConflict?.remoteVersion, 4)
        let queued = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(queued.status, .pending)
        let stillLocal = try await env.local.customers.fetch(id: local.id)
        XCTAssertEqual(stillLocal.name, "Yerel-yeni")
    }

    func testCompletedLocalVersusInProgressRemoteDoesNotReopen() async throws {
        let env = try makeEnvironment()
        let local = DomainFixtures.workOrder(status: .completed, completedAt: now)
        let remote = DomainFixtures.workOrder(status: .inProgress)
        try await env.local.workOrders.save(local)
        try await env.remoteWorkOrders.save(remote)

        let outcome = try await env.engine.reconcile(
            request(entityType: .workOrder, entityId: local.id.rawValue, versions: v(1, 2, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .conflict)
        let stored = try await env.local.workOrders.fetch(id: local.id)
        XCTAssertEqual(stored.status, .completed)
    }

    func testInProgressLocalVersusCompletedRemoteDoesNotReopen() async throws {
        let env = try makeEnvironment()
        let local = DomainFixtures.workOrder(status: .inProgress)
        let remote = DomainFixtures.workOrder(status: .completed, completedAt: now)
        try await env.local.workOrders.save(local)
        try await env.remoteWorkOrders.save(remote)

        let outcome = try await env.engine.reconcile(
            request(entityType: .workOrder, entityId: local.id.rawValue, versions: v(1, 2, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .conflict)
        let stored = try await env.local.workOrders.fetch(id: local.id)
        XCTAssertEqual(stored.status, .inProgress)
        XCTAssertNotEqual(stored.status, .completed)
    }

    func testBothCompletedAndEqualIsNoChange() async throws {
        let env = try makeEnvironment()
        let order = DomainFixtures.workOrder(status: .completed, completedAt: now)
        try await env.local.workOrders.save(order)
        try await env.remoteWorkOrders.save(order)

        let outcome = try await env.engine.reconcile(
            request(entityType: .workOrder, entityId: order.id.rawValue, versions: v(3, 3, 3)),
            now: now
        )
        XCTAssertEqual(outcome.result, .noChange)
        let stored = try await env.local.workOrders.fetch(id: order.id)
        XCTAssertEqual(stored.status, .completed)
    }

    func testRemoteMissingWithPendingMutationDoesNotDeleteLocal() async throws {
        let env = try makeEnvironment()
        let customer = DomainFixtures.customer(name: "Kalsın")
        try await env.local.customers.save(customer)
        let operation = try pendingUpdate(entityId: customer.id.rawValue, localVersion: 2, remoteVersion: 1)
        try await env.queue.enqueue(operation)

        let outcome = try await env.engine.reconcile(
            request(entityId: customer.id.rawValue, versions: v(2, 1, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .keepLocal)
        _ = try await env.local.customers.fetch(id: customer.id)
        let queued = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(queued.status, .pending)
    }

    func testRemoteMissingWithoutMutationIsConflictAndKeepsLocal() async throws {
        let env = try makeEnvironment()
        let customer = DomainFixtures.customer(name: "Silinmesin")
        try await env.local.customers.save(customer)

        let outcome = try await env.engine.reconcile(
            request(entityId: customer.id.rawValue, versions: v(1, 2, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .conflict)
        _ = try await env.local.customers.fetch(id: customer.id)
    }

    func testSucceededOperationIsNotTreatedAsPendingMutation() async throws {
        let env = try makeEnvironment()
        let customer = DomainFixtures.customer(name: "Ack")
        try await env.local.customers.save(customer)
        try await env.remoteCustomers.save(customer)
        var operation = try pendingUpdate(entityId: customer.id.rawValue, localVersion: 1, remoteVersion: 1)
        try await env.queue.enqueue(operation)
        operation.status = .inProgress
        operation.updatedAt = now
        try await env.queue.update(operation)
        operation.status = .succeeded
        operation.updatedAt = now.addingTimeInterval(1)
        try await env.queue.update(operation)

        let outcome = try await env.engine.reconcile(
            request(entityId: customer.id.rawValue, versions: v(1, 1, 1)),
            now: now
        )
        XCTAssertEqual(outcome.result, .noChange)
        XCTAssertFalse(outcome.facts.hasPendingLocalMutation)
        let queued = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(queued.status, .succeeded)
    }

    func testEditRequestIsNotAutoApprovedOntoWorkOrder() async throws {
        let env = try makeEnvironment()
        let order = DomainFixtures.workOrder(status: .completed, completedAt: now)
        let localRequest = DomainFixtures.editRequest(status: .pending)
        var remoteRequest = localRequest
        remoteRequest.status = .approved
        remoteRequest.reviewedByUserId = UserID("user-operator-1")
        remoteRequest.reviewedAt = now
        try await env.local.workOrders.save(order)
        try await env.local.editRequests.save(localRequest)
        try await env.remoteEditRequests.save(remoteRequest)

        let outcome = try await env.engine.reconcile(
            request(
                entityType: .editRequest,
                entityId: localRequest.id.rawValue,
                versions: v(1, 2, 1)
            ),
            now: now
        )
        XCTAssertEqual(outcome.result, .conflict)
        let storedRequest = try await env.local.editRequests.fetch(id: localRequest.id)
        XCTAssertEqual(storedRequest.status, .pending)
        let storedOrder = try await env.local.workOrders.fetch(id: order.id)
        XCTAssertEqual(storedOrder.status, .completed)
        XCTAssertEqual(storedOrder.issueDescription, order.issueDescription)
    }

    // MARK: - Environment

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let engine: RemoteToLocalReconciliationEngine
        let remoteCustomers: InMemoryCustomerRepository
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let remoteEditRequests: InMemoryEditRequestRepository
    }

    private func makeEnvironment() throws -> Environment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let editRequests = InMemoryEditRequestRepository()
        var remoteRepos = remote.repositories
        remoteRepos.editRequests = SpyingEditRequestRepository(inner: editRequests, probe: probe)
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
        let engine = RemoteToLocalReconciliationEngine(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: localEntities,
            remote: remoteRepos
        )
        return Environment(
            local: local,
            queue: local.syncOperations,
            engine: engine,
            remoteCustomers: remote.customers,
            remoteWorkOrders: remote.workOrders,
            remoteEditRequests: editRequests
        )
    }

    private func request(
        entityType: SyncEntityType = .customer,
        entityId: String,
        parentId: String? = nil,
        versions: ReconciliationVersionState
    ) -> ReconciliationRequest {
        ReconciliationRequest(
            entityType: entityType,
            entityId: entityId,
            parentId: parentId,
            versions: versions
        )
    }

    private func v(_ local: Int?, _ remote: Int?, _ lastSynced: Int?) -> ReconciliationVersionState {
        ReconciliationVersionState(
            localVersion: local,
            remoteVersion: remote,
            lastSyncedRemoteVersion: lastSynced
        )
    }

    private func pendingUpdate(
        entityId: String,
        localVersion: Int,
        remoteVersion: Int
    ) throws -> SyncOperation {
        try SyncOperation.pending(
            entityType: .customer,
            entityId: entityId,
            operationType: .update,
            createdAt: now,
            localVersion: localVersion,
            remoteVersion: remoteVersion
        )
    }
}
