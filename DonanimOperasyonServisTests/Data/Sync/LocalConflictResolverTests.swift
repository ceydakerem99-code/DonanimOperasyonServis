import XCTest
@testable import DonanimOperasyonServis

final class LocalConflictResolverTests: XCTestCase {

    private let now = DomainFixtures.referenceDate
    private let operatorUser = DomainFixtures.operatorUser()

    func testPersistingUnresolvedConflictListsIt() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env)
        let listed = try await env.conflicts.listUnresolved()
        XCTAssertEqual(listed.map(\.id), [conflict.id])
        XCTAssertEqual(listed.first?.status, .unresolved)
        XCTAssertNil(listed.first?.resolution)
    }

    func testAuthorizedOperatorUseLocalKeepsLocalEntity() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env, advanceLinkedToConflict: true)
        let outcome = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useLocal,
            actor: operatorUser,
            now: now
        )
        XCTAssertEqual(outcome.decision, .useLocal)
        XCTAssertEqual(outcome.conflict.resolution, .useLocal)
        XCTAssertFalse(outcome.didApplyRemote)
        let stored = try await env.local.customers.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(stored.name, "Yerel")
        let remote = try await env.remoteCustomers.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(remote.name, "Sunucu")
    }

    func testAuthorizedOperatorUseRemoteAppliesDomainEntityToLocal() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env)
        let outcome = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useRemote,
            actor: operatorUser,
            now: now
        )
        XCTAssertEqual(outcome.decision, .useRemote)
        XCTAssertTrue(outcome.didApplyRemote)
        XCTAssertNil(outcome.enqueueOutcome)
        let stored = try await env.local.customers.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(stored.name, "Sunucu")
        let remote = try await env.remoteCustomers.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(stored, remote)
    }

    func testUnauthorizedActorCannotResolve() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env)
        for actor in [DomainFixtures.technicianUser(), DomainFixtures.adminUser()] {
            await XCTAssertThrowsErrorAsync(
                try await env.resolver.resolve(
                    conflictID: conflict.id,
                    decision: .useLocal,
                    actor: actor,
                    now: now
                )
            ) { error in
                XCTAssertEqual(
                    error as? DomainError,
                    .unauthorized(action: .resolveSyncConflict)
                )
            }
        }
        let stored = try await env.conflicts.fetch(id: conflict.id)
        XCTAssertNil(stored.resolution)
        let local = try await env.local.customers.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(local.name, "Yerel")
    }

    func testUnresolvedDecisionIsDeterministic() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env)
        let first = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .unresolved,
            actor: operatorUser,
            now: now
        )
        let second = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .unresolved,
            actor: operatorUser,
            now: now.addingTimeInterval(5)
        )
        XCTAssertEqual(first.decision, .unresolved)
        XCTAssertEqual(second.decision, .unresolved)
        XCTAssertEqual(first.conflict, second.conflict)
        XCTAssertNil(first.conflict.resolution)
        XCTAssertEqual(first.conflict.localVersion, conflict.localVersion)
        let listed = try await env.conflicts.listUnresolved()
        XCTAssertEqual(listed.map(\.id), [conflict.id])
    }

    func testResolvingTheSameConflictTwiceDoesNotEnqueueAgain() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env, advanceLinkedToConflict: true)
        let first = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useLocal,
            actor: operatorUser,
            now: now
        )
        guard case .inserted = first.enqueueOutcome else {
            return XCTFail("Expected a new outbound operation on first useLocal")
        }
        let afterFirst = try await env.queue.list(entityType: .customer, entityId: "cust-1")
        let second = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useLocal,
            actor: operatorUser,
            now: now.addingTimeInterval(2)
        )
        XCTAssertNil(second.enqueueOutcome)
        XCTAssertEqual(second.decision, .useLocal)
        XCTAssertFalse(second.didApplyRemote)
        let afterSecond = try await env.queue.list(entityType: .customer, entityId: "cust-1")
        XCTAssertEqual(afterSecond.map(\.id), afterFirst.map(\.id))
    }

    func testUseLocalEnqueuesIdempotentSyncOperationWhenLinkedIsConflict() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env, advanceLinkedToConflict: true)
        let outcome = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useLocal,
            actor: operatorUser,
            now: now
        )
        guard case .inserted(let inserted) = outcome.enqueueOutcome else {
            return XCTFail("Expected inserted SyncOperation")
        }
        XCTAssertEqual(inserted.status, .pending)
        XCTAssertEqual(inserted.entityType, .customer)
        XCTAssertEqual(inserted.entityId, "cust-1")
        XCTAssertEqual(
            inserted.idempotencyKey,
            SyncIdempotencyKey.make(
                entityType: .customer,
                entityId: "cust-1",
                operationType: .update,
                localVersion: inserted.localVersion
            )
        )
        let duplicate = try await env.queue.enqueue(inserted)
        guard case .duplicate(let existing) = duplicate else {
            return XCTFail("Expected idempotent duplicate")
        }
        XCTAssertEqual(existing.id, inserted.id)
    }

    func testCompletedWorkOrderConflictStaysUnresolved() async throws {
        let env = try makeEnvironment()
        let local = DomainFixtures.workOrder(status: .completed, completedAt: now)
        let remote = DomainFixtures.workOrder(status: .inProgress)
        try await env.local.workOrders.save(local)
        try await env.remoteWorkOrders.save(remote)
        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-wo-completed"),
            syncOperationId: SyncOperationID("op-wo-completed"),
            entityType: .workOrder,
            entityId: local.id.rawValue,
            localVersion: 2,
            remoteVersion: 3,
            localReference: "local/wo-1",
            remoteReference: "remote/wo-1",
            detectedAt: now
        )
        try await env.conflicts.save(conflict)

        await XCTAssertThrowsErrorAsync(
            try await env.resolver.resolve(
                conflictID: conflict.id,
                decision: .useLocal,
                actor: operatorUser,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "conflict.completedWorkOrderMustStayUnresolved")
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await env.resolver.resolve(
                conflictID: conflict.id,
                decision: .useRemote,
                actor: operatorUser,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "conflict.completedWorkOrderMustStayUnresolved")
            )
        }

        let leaveOpen = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .unresolved,
            actor: operatorUser,
            now: now
        )
        XCTAssertEqual(leaveOpen.decision, .unresolved)
        XCTAssertNil(leaveOpen.conflict.resolution)
        let storedLocal = try await env.local.workOrders.fetch(id: local.id)
        XCTAssertEqual(storedLocal.status, .completed)
        let storedRemote = try await env.remoteWorkOrders.fetch(id: remote.id)
        XCTAssertEqual(storedRemote.status, .inProgress)
    }

    func testInProgressLocalVersusCompletedRemoteAlsoStaysUnresolved() async throws {
        let env = try makeEnvironment()
        let local = DomainFixtures.workOrder(status: .inProgress)
        let remote = DomainFixtures.workOrder(status: .completed, completedAt: now)
        try await env.local.workOrders.save(local)
        try await env.remoteWorkOrders.save(remote)
        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-wo-remote-completed"),
            syncOperationId: SyncOperationID("op-wo-remote-completed"),
            entityType: .workOrder,
            entityId: local.id.rawValue,
            localVersion: 1,
            remoteVersion: 4,
            detectedAt: now
        )
        try await env.conflicts.save(conflict)

        await XCTAssertThrowsErrorAsync(
            try await env.resolver.resolve(
                conflictID: conflict.id,
                decision: .useRemote,
                actor: operatorUser,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "conflict.completedWorkOrderMustStayUnresolved")
            )
        }
        let stored = try await env.local.workOrders.fetch(id: local.id)
        XCTAssertEqual(stored.status, .inProgress)
    }

    func testEditRequestWorkflowIsNotBypassed() async throws {
        let env = try makeEnvironment()
        let order = DomainFixtures.workOrder(status: .completed, completedAt: now)
        let localRequest = DomainFixtures.editRequest(status: .pending)
        var remoteRequest = localRequest
        remoteRequest.status = .approved
        remoteRequest.reviewedByUserId = operatorUser.id
        remoteRequest.reviewedAt = now
        try await env.local.workOrders.save(order)
        try await env.local.editRequests.save(localRequest)
        try await env.remoteEditRequests.save(remoteRequest)
        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-er"),
            syncOperationId: SyncOperationID("op-er"),
            entityType: .editRequest,
            entityId: localRequest.id.rawValue,
            localVersion: 1,
            remoteVersion: 2,
            detectedAt: now
        )
        try await env.conflicts.save(conflict)

        await XCTAssertThrowsErrorAsync(
            try await env.resolver.resolve(
                conflictID: conflict.id,
                decision: .useRemote,
                actor: operatorUser,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "conflict.editRequestWorkflowRequired")
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await env.resolver.resolve(
                conflictID: conflict.id,
                decision: .useLocal,
                actor: operatorUser,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "conflict.editRequestWorkflowRequired")
            )
        }

        let storedRequest = try await env.local.editRequests.fetch(id: localRequest.id)
        XCTAssertEqual(storedRequest.status, .pending)
        let storedOrder = try await env.local.workOrders.fetch(id: order.id)
        XCTAssertEqual(storedOrder.status, .completed)
        XCTAssertEqual(storedOrder.issueDescription, order.issueDescription)
        let stillOpen = try await env.conflicts.fetch(id: conflict.id)
        XCTAssertNil(stillOpen.resolution)
    }

    func testResolutionPreservesDetectionSnapshot() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env, advanceLinkedToConflict: true)
        let outcome = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useLocal,
            actor: operatorUser,
            now: now.addingTimeInterval(40)
        )
        XCTAssertEqual(outcome.conflict.localVersion, 2)
        XCTAssertEqual(outcome.conflict.remoteVersion, 4)
        XCTAssertEqual(outcome.conflict.localReference, "local/cust-1")
        XCTAssertEqual(outcome.conflict.remoteReference, "remote/cust-1")
        XCTAssertEqual(outcome.conflict.detectedAt, now)
        XCTAssertEqual(outcome.conflict.resolvedAt, now.addingTimeInterval(40))
        XCTAssertEqual(outcome.conflict.resolvedByUserId, operatorUser.id)
    }

    func testResolvedConflictRowIsNotPhysicallyDeleted() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env)
        _ = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useRemote,
            actor: operatorUser,
            now: now
        )
        let fetched = try await env.conflicts.fetch(id: conflict.id)
        XCTAssertEqual(fetched.id, conflict.id)
        XCTAssertEqual(fetched.resolution, .useRemote)
        let open = try await env.conflicts.listUnresolved()
        XCTAssertTrue(open.isEmpty)
    }

    func testLinkedSyncOperationIsNotSentWhileConflictIsUnresolved() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env, advanceLinkedToConflict: false)
        let pending = try await env.queue.fetch(id: conflict.syncOperationId)
        XCTAssertEqual(pending.status, .pending)

        try await env.manager.syncPending(now: now)
        let writesBefore = await env.probe.recordedWrites()
        XCTAssertTrue(writesBefore.isEmpty)
        let stillPending = try await env.queue.fetch(id: pending.id)
        XCTAssertEqual(stillPending.status, .pending)

        _ = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useRemote,
            actor: operatorUser,
            now: now
        )
        try await env.manager.syncPending(now: now)
        let writesAfterRemote = await env.probe.recordedWrites()
        XCTAssertTrue(writesAfterRemote.isEmpty)
        let local = try await env.local.customers.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(local.name, "Sunucu")
    }

    func testUseLocalLiftsHoldSoExistingPendingOperationCanSync() async throws {
        let env = try makeEnvironment()
        let conflict = try await seedCustomerConflict(env, advanceLinkedToConflict: false)
        let outcome = try await env.resolver.resolve(
            conflictID: conflict.id,
            decision: .useLocal,
            actor: operatorUser,
            now: now
        )
        guard case .duplicate(let existing) = outcome.enqueueOutcome else {
            return XCTFail("Expected to reuse the pending linked operation")
        }
        XCTAssertEqual(existing.id, conflict.syncOperationId)

        try await env.manager.syncPending(now: now)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, "cust-1")])
        let stored = try await env.queue.fetch(id: existing.id)
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
        let remoteEditRequests: InMemoryEditRequestRepository
        let resolver: LocalConflictResolver
        let manager: LocalToRemoteSyncManager
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
        let resolver = LocalConflictResolver(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: localEntities,
            remote: remoteRepos
        )
        let manager = LocalToRemoteSyncManager(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: localEntities,
            remote: remoteRepos
        )
        return Environment(
            local: local,
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            probe: probe,
            remoteCustomers: remote.customers,
            remoteWorkOrders: remote.workOrders,
            remoteEditRequests: editRequests,
            resolver: resolver,
            manager: manager
        )
    }

    @discardableResult
    private func seedCustomerConflict(
        _ env: Environment,
        advanceLinkedToConflict: Bool = false
    ) async throws -> SyncConflict {
        let local = DomainFixtures.customer(name: "Yerel")
        var remote = DomainFixtures.customer(name: "Sunucu")
        remote.updatedAt = now.addingTimeInterval(60)
        try await env.local.customers.save(local)
        try await env.remoteCustomers.save(remote)

        var operation = try SyncOperation.pending(
            id: SyncOperationID("op-cust-1"),
            entityType: .customer,
            entityId: local.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            remoteVersion: 1
        )
        _ = try await env.queue.enqueue(operation)
        if advanceLinkedToConflict {
            operation.status = .inProgress
            operation.updatedAt = now
            try await env.queue.update(operation)
            operation.status = .conflict
            operation.updatedAt = now.addingTimeInterval(1)
            try await env.queue.update(operation)
        }

        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-cust-1"),
            syncOperationId: operation.id,
            entityType: .customer,
            entityId: local.id.rawValue,
            localVersion: 2,
            remoteVersion: 4,
            localReference: "local/cust-1",
            remoteReference: "remote/cust-1",
            detectedAt: now
        )
        try await env.conflicts.save(conflict)
        return conflict
    }
}
