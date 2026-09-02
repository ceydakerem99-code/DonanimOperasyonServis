import XCTest
@testable import DonanimOperasyonServis

/// Regression: offline complete must not push WorkOrder `.completed`
/// to remote before the `.completed` GPS create succeeds (Firestore
/// rules reject location create after the parent is completed).
final class CompletedGPSSyncOrderingTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    func testWorkOrderCompletionDependsOnCompletedGPSCreate() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let service = makeService(local: env.local, queue: env.queue)

        let completedGPS = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .completed,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 4)
        )
        _ = try await service.complete(
            actor: tech,
            orderId: order.id,
            completedLocationId: completedGPS.id,
            at: now
        )

        let gpsOps = try await env.queue.list(
            entityType: .workOrderLocation,
            entityId: completedGPS.id
        )
        let gpsCreate = try XCTUnwrap(gpsOps.first { $0.operationType == .create })
        XCTAssertEqual(gpsCreate.status, .pending)

        let woOps = try await env.queue.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        let woUpdate = try XCTUnwrap(woOps.first { $0.operationType == .update })
        XCTAssertEqual(woUpdate.dependsOnOperationId, gpsCreate.id)
        XCTAssertEqual(woUpdate.status, .pending)

        // Simulate WO draining before GPS (worst order).
        try await env.manager.sync(operation: woUpdate, now: now)
        var heldWO = try await env.queue.fetch(id: woUpdate.id)
        XCTAssertEqual(heldWO.status, .pending)
        var writes = await env.probe.recordedWrites()
        XCTAssertFalse(writes.contains(.save(.workOrder, order.id.rawValue)))
        XCTAssertFalse(writes.contains(.save(.workOrderLocation, completedGPS.id)))

        // GPS create first → then WO may proceed.
        try await env.manager.sync(operation: gpsCreate, now: now)
        let syncedGPS = try await env.queue.fetch(id: gpsCreate.id)
        XCTAssertEqual(syncedGPS.status, .succeeded)
        writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.contains(.save(.workOrderLocation, completedGPS.id)))
        XCTAssertFalse(writes.contains(.save(.workOrder, order.id.rawValue)))

        try await env.manager.sync(operation: woUpdate, now: now)
        heldWO = try await env.queue.fetch(id: woUpdate.id)
        XCTAssertEqual(heldWO.status, .succeeded)
        writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.contains(.save(.workOrder, order.id.rawValue)))
    }

    /// A completed work order must leave one durable local survey, queue the
    /// same id for remote delivery, and write that exact id remotely. This is
    /// the id carried by the customer-facing survey token.
    func testCompletionCreatesAndSyncsCustomerSatisfactionWithTokenID() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let service = makeService(local: env.local, queue: env.queue)
        let completedGPS = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .completed,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 4)
        )

        _ = try await service.complete(
            actor: tech,
            orderId: order.id,
            completedLocationId: completedGPS.id,
            at: now
        )

        let satisfaction = try await awaitCustomerSatisfaction(
            local: env.local,
            orderId: order.id
        )
        XCTAssertEqual(satisfaction.workOrderId, order.id)
        XCTAssertEqual(satisfaction.customerId, order.customerId)
        XCTAssertEqual(satisfaction.status, .pending)
        let fetchedLocal = try await env.local.customerSatisfactions.fetch(id: satisfaction.id)
        XCTAssertEqual(fetchedLocal.id, satisfaction.id)

        let surveyOps = try await env.queue.list(
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue
        )
        let surveyCreate = try XCTUnwrap(surveyOps.first { $0.operationType == .create })
        let workOrderOps = try await env.queue.list(entityType: .workOrder, entityId: order.id.rawValue)
        XCTAssertEqual(surveyCreate.dependsOnOperationId, try XCTUnwrap(workOrderOps.first).id)

        _ = try await env.manager.syncPending(now: now)
        let remote = try await env.remoteEntities.customerSatisfactions.fetch(id: satisfaction.id)
        XCTAssertEqual(remote.id, satisfaction.id)
        XCTAssertEqual(remote.workOrderId, order.id)

        let token = CustomerSatisfactionSurveyToken.generate(satisfactionId: satisfaction.id)
        let encodedID = try XCTUnwrap(token.split(separator: ".").first)
        let padded = String(encodedID)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - encodedID.count % 4) % 4)
        XCTAssertEqual(String(data: try XCTUnwrap(Data(base64Encoded: padded)), encoding: .utf8), satisfaction.id.rawValue)

        let autoCreate = CreateCustomerSatisfactionUseCase(
            workOrderRepository: env.local.workOrders,
            customerSatisfactionRepository: env.local.customerSatisfactions
        )
        let duplicate = try await autoCreate.executeOnWorkOrderCompletion(
            actor: tech,
            orderId: order.id,
            at: now
        )
        XCTAssertNil(duplicate)
        let allLocal = try await env.local.customerSatisfactions.list(for: order.id)
        XCTAssertEqual(allLocal.count, 1)
    }

    func testCustomerSatisfactionSyncsAfterPrunedWorkOrderDependency() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let service = makeService(local: env.local, queue: env.queue)
        let completedGPS = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .completed,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 4)
        )
        _ = try await service.complete(
            actor: tech,
            orderId: order.id,
            completedLocationId: completedGPS.id,
            at: now
        )

        let satisfaction = try await awaitCustomerSatisfaction(
            local: env.local,
            orderId: order.id
        )
        let csOps = try await env.queue.list(
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue
        )
        let csCreate = try XCTUnwrap(csOps.first { $0.operationType == .create })
        let gpsOps = try await env.queue.list(
            entityType: .workOrderLocation,
            entityId: completedGPS.id
        )
        let gpsCreate = try XCTUnwrap(gpsOps.first { $0.operationType == .create })
        let woOps = try await env.queue.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        let woUpdate = try XCTUnwrap(woOps.first { $0.operationType == .update })

        try await env.manager.sync(operation: gpsCreate, now: now)
        try await env.manager.sync(operation: woUpdate, now: now)
        try await env.queue.deleteCompleted()

        var heldCS = try await env.queue.fetch(id: csCreate.id)
        XCTAssertEqual(heldCS.status, .pending)

        try await env.manager.sync(operation: heldCS, now: now)
        heldCS = try await env.queue.fetch(id: csCreate.id)
        XCTAssertEqual(heldCS.status, .succeeded)

        let remote = try await env.remoteEntities.customerSatisfactions.fetch(id: satisfaction.id)
        XCTAssertEqual(remote.id, satisfaction.id)
        XCTAssertEqual(remote.workOrderId, order.id)
    }

    func testIdempotentWorkOrderUpdateWhenRemoteAlreadyCompleted() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let service = makeService(local: env.local, queue: env.queue)
        let completedGPS = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .completed,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 4)
        )
        let gpsOps = try await env.queue.list(
            entityType: .workOrderLocation,
            entityId: completedGPS.id
        )
        let gpsCreate = try XCTUnwrap(gpsOps.first { $0.operationType == .create })
        try await env.manager.sync(operation: gpsCreate, now: now)

        var completedOrder = try await env.local.workOrders.fetch(id: order.id)
        completedOrder.status = .completed
        completedOrder.completedAt = now
        completedOrder.updatedAt = now
        try await env.local.workOrders.save(completedOrder)
        try await env.remoteWorkOrders.save(completedOrder)

        let woUpdate = try SyncOperation.pending(
            id: SyncOperationID("op-wo-idempotent"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 3,
            workOrderStatus: .completed,
            allowsCompletedWorkOrderUpdate: true,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(woUpdate)

        let writesBefore = await env.probe.recordedWrites()
        try await env.manager.sync(operation: woUpdate, now: now)
        let synced = try await env.queue.fetch(id: woUpdate.id)
        XCTAssertEqual(synced.status, .succeeded)

        let writesAfter = await env.probe.recordedWrites()
        let beforeCount = writesBefore.filter { $0 == .save(.workOrder, order.id.rawValue) }.count
        let afterCount = writesAfter.filter { $0 == .save(.workOrder, order.id.rawValue) }.count
        XCTAssertEqual(afterCount, beforeCount)
    }

    func testStalePreCompletionWorkOrderUpdatesAreAcknowledgedWithoutGPSWait() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let service = makeService(local: env.local, queue: env.queue)
        let staleUpdate = try SyncOperation.pending(
            id: SyncOperationID("op-stale-inprogress"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 1,
            workOrderStatus: .inProgress,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(staleUpdate)
        let completedGPS = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .completed,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 4)
        )
        _ = try await service.complete(
            actor: tech,
            orderId: order.id,
            completedLocationId: completedGPS.id,
            at: now
        )

        let staleUpdates = try await env.queue.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        ).filter {
            $0.operationType == .update && $0.dependsOnOperationId == nil && $0.status == .pending
        }
        XCTAssertFalse(staleUpdates.isEmpty)

        for stale in staleUpdates {
            try await env.manager.sync(operation: stale, now: now)
            let synced = try await env.queue.fetch(id: stale.id)
            XCTAssertEqual(synced.status, .succeeded)
        }

        let completionUpdate = try await env.queue.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        ).first { $0.dependsOnOperationId != nil && $0.status == .pending }
        XCTAssertNotNil(completionUpdate)
    }

    func testDrainCountsHeldOperationsOncePerDrain() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let service = makeService(local: env.local, queue: env.queue)
        let completedGPS = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .completed,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 4)
        )
        _ = try await service.complete(
            actor: tech,
            orderId: order.id,
            completedLocationId: completedGPS.id,
            at: now
        )

        let pendingBefore = try await env.queue.fetch(status: .pending)
        XCTAssertGreaterThan(pendingBefore.count, 0)

        _ = try await env.manager.syncPending(now: now)
        let report = await env.manager.lastDrainReport()
        XCTAssertNotNil(report)
        XCTAssertLessThanOrEqual(report?.held ?? 0, report?.pendingAtStart ?? 0)
    }

    func testBeltAndSuspendersHoldsCompletedWOWithoutExplicitDependency() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        var order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let location = DomainFixtures.location(
            id: "loc-completed-orphan",
            workOrderId: order.id,
            event: .completed,
            capturedByUserId: tech.id
        )
        try await env.local.locations.save(location)

        let gpsCreate = try SyncOperation.pending(
            id: SyncOperationID("op-gps-pending"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(gpsCreate)

        order.status = .completed
        order.completedAt = now
        order.updatedAt = now
        try await env.local.workOrders.save(order)

        let woUpdate = try SyncOperation.pending(
            id: SyncOperationID("op-wo-completed"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            workOrderStatus: .completed,
            allowsCompletedWorkOrderUpdate: true
        )
        XCTAssertNil(woUpdate.dependsOnOperationId)
        _ = try await env.queue.enqueue(woUpdate)

        try await env.manager.sync(operation: woUpdate, now: now)
        let held = try await env.queue.fetch(id: woUpdate.id)
        XCTAssertEqual(held.status, .pending)
        let writes = await env.probe.recordedWrites()
        XCTAssertFalse(writes.contains(.save(.workOrder, order.id.rawValue)))
    }

    func testPermanentlyFailedGPSMarksWorkOrderDependencyBlockedWithoutAbortingDrain() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        var order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let location = DomainFixtures.location(
            id: "loc-completed-failed",
            workOrderId: order.id,
            event: .completed,
            capturedByUserId: tech.id
        )
        try await env.local.locations.save(location)

        var gpsCreate = try SyncOperation.pending(
            id: SyncOperationID("op-gps-failed"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(gpsCreate)
        var running = try await env.queue.fetch(id: gpsCreate.id)
        running.status = .inProgress
        running.updatedAt = now
        try await env.queue.update(running)
        running.status = .failed
        running.errorMessage = SyncError.invalidPayload.diagnosticMessage
        running.retryCount = 1
        running.lastAttemptAt = now
        running.updatedAt = now
        try await env.queue.update(running)

        order.status = .completed
        order.completedAt = now
        order.updatedAt = now
        try await env.local.workOrders.save(order)

        let woUpdate = try SyncOperation.pending(
            id: SyncOperationID("op-wo-blocked"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            workOrderStatus: .completed,
            dependsOnOperationId: gpsCreate.id,
            allowsCompletedWorkOrderUpdate: true
        )
        _ = try await env.queue.enqueue(woUpdate)

        let outcome = try await env.manager.syncPending(now: now)
        XCTAssertEqual(outcome, .completed)

        let blockedWO = try await env.queue.fetch(id: woUpdate.id)
        XCTAssertEqual(blockedWO.status, .failed)
        XCTAssertTrue(blockedWO.errorMessage?.hasPrefix("dependencyBlocked:") == true)
    }

    func testDependencyBlockedWorkOrderRetriesAfterGPSSucceedsInSameDrain() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let location = DomainFixtures.location(
            id: "loc-requeue",
            workOrderId: order.id,
            event: .completed,
            capturedByUserId: tech.id
        )
        try await env.local.locations.save(location)

        var gpsCreate = try SyncOperation.pending(
            id: SyncOperationID("op-gps-requeue"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(gpsCreate)

        var orderCompleted = try await env.local.workOrders.fetch(id: order.id)
        orderCompleted.status = .completed
        orderCompleted.completedAt = now
        orderCompleted.updatedAt = now
        try await env.local.workOrders.save(orderCompleted)

        let woUpdate = try SyncOperation.pending(
            id: SyncOperationID("op-wo-requeue"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            workOrderStatus: .completed,
            dependsOnOperationId: gpsCreate.id,
            allowsCompletedWorkOrderUpdate: true
        )
        _ = try await env.queue.enqueue(woUpdate)

        // Simulate a prior drain that blocked the WO while GPS was still failing.
        var running = try await env.queue.fetch(id: gpsCreate.id)
        running.status = .inProgress
        try await env.queue.update(running)
        running.status = .failed
        running.errorMessage = SyncError.unauthorized.diagnosticMessage
        running.retryCount = 1
        running.lastAttemptAt = now
        try await env.queue.update(running)

        var blocked = try await env.queue.fetch(id: woUpdate.id)
        blocked.status = .inProgress
        try await env.queue.update(blocked)
        blocked.status = .failed
        blocked.errorMessage = SyncError.dependencyBlocked(
            blockingOperationId: gpsCreate.id.rawValue,
            underlying: SyncError.unauthorized.diagnosticMessage
        ).diagnosticMessage
        blocked.retryCount = 1
        blocked.lastAttemptAt = now
        try await env.queue.update(blocked)

        try await env.queue.prepareRetry(id: gpsCreate.id)

        let outcome = try await env.manager.syncPending(now: now)
        XCTAssertEqual(outcome, .completed)

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: gpsCreate.id))
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: woUpdate.id))
    }

    func testRemoteAlreadyCompletedAcknowledgesStuckCompletionChainAndUnblocksCustomerSatisfaction() async throws {
        let env = try makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        var order = try await seedCompletableOrder(
            local: env.local,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let location = DomainFixtures.location(
            id: "loc-mehmet-stuck",
            workOrderId: order.id,
            event: .completed,
            capturedByUserId: tech.id
        )
        try await env.local.locations.save(location)

        let gpsCreate = try SyncOperation.pending(
            id: SyncOperationID("op-gps-mehmet"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(gpsCreate)

        order.status = .completed
        order.completedAt = now
        order.updatedAt = now
        try await env.local.workOrders.save(order)
        try await env.remoteWorkOrders.save(order)

        var woUpdate = try SyncOperation.pending(
            id: SyncOperationID("op-wo-mehmet"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            workOrderStatus: .completed,
            dependsOnOperationId: gpsCreate.id,
            allowsCompletedWorkOrderUpdate: true,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(woUpdate)
        var runningWO = try await env.queue.fetch(id: woUpdate.id)
        runningWO.errorMessage = SyncError.unauthorized.diagnosticMessage
        runningWO.retryCount = 1
        runningWO.updatedAt = now
        try await env.queue.update(runningWO)

        let satisfaction = DomainFixtures.customerSatisfaction(
            id: CustomerSatisfactionID("cs-mehmet"),
            workOrderId: order.id
        )
        try await env.local.customerSatisfactions.save(satisfaction)
        var csCreate = try SyncOperation.pending(
            id: SyncOperationID("op-cs-mehmet"),
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1,
            dependsOnOperationId: woUpdate.id,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(csCreate)
        var runningCS = try await env.queue.fetch(id: csCreate.id)
        runningCS.status = .inProgress
        runningCS.updatedAt = now
        try await env.queue.update(runningCS)
        runningCS.status = .failed
        runningCS.errorMessage = SyncError.dependencyBlocked(
            blockingOperationId: woUpdate.id.rawValue,
            underlying: SyncError.unauthorized.diagnosticMessage
        ).diagnosticMessage
        runningCS.retryCount = 1
        runningCS.lastAttemptAt = now
        runningCS.updatedAt = now
        try await env.queue.update(runningCS)

        let outcome = try await env.manager.syncPending(now: now)
        XCTAssertEqual(outcome, .completed)

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: gpsCreate.id))
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: woUpdate.id))
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: csCreate.id))
        let remoteCS = try await env.remoteEntities.customerSatisfactions.fetch(id: satisfaction.id)
        XCTAssertEqual(remoteCS.workOrderId, order.id)
    }

    func testRestartSafeOrderingAfterQueueReload() async throws {
        let harness = try SwiftDataTestHarness()
        var env = try makeEnvironment(local: harness)
        let tech = DomainFixtures.technicianUser()
        let order = try await seedCompletableOrder(
            local: harness,
            tech: tech,
            remoteWorkOrders: env.remoteWorkOrders
        )
        let queue = harness.syncOperations
        let service = makeService(local: harness, queue: queue)

        let completedGPS = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .completed,
            coordinate: LocationCoordinate(latitude: 41.1, longitude: 29.1, accuracy: 5)
        )
        _ = try await service.complete(
            actor: tech,
            orderId: order.id,
            completedLocationId: completedGPS.id,
            at: now
        )

        // New manager instance = app relaunch with same SwiftData queue.
        env = try makeEnvironment(local: harness)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(order, on: env.remoteWorkOrders)
        let gpsOps = try await queue.list(
            entityType: .workOrderLocation,
            entityId: completedGPS.id
        )
        let gpsCreate = try XCTUnwrap(gpsOps.first { $0.operationType == .create })
        let woOps = try await queue.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        let woUpdate = try XCTUnwrap(woOps.first { $0.operationType == .update })
        XCTAssertEqual(woUpdate.dependsOnOperationId, gpsCreate.id)

        try await env.manager.sync(operation: woUpdate, now: now)
        let heldAfterRelaunch = try await queue.fetch(id: woUpdate.id)
        XCTAssertEqual(heldAfterRelaunch.status, .pending)

        // One syncPending pass drains GPS then re-visits WO completion.
        try await env.manager.syncPending(now: now)
        await XCTAssertThrowsErrorAsync(try await queue.fetch(id: gpsCreate.id))
        await XCTAssertThrowsErrorAsync(try await queue.fetch(id: woUpdate.id))

        let writes = await env.probe.recordedWrites()
        let gpsIndex = try XCTUnwrap(
            writes.firstIndex(of: .save(.workOrderLocation, completedGPS.id))
        )
        let woIndex = try XCTUnwrap(
            writes.firstIndex(of: .save(.workOrder, order.id.rawValue))
        )
        XCTAssertLessThan(gpsIndex, woIndex)
    }

    // MARK: - Helpers

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let probe: SyncRemoteProbe
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let remoteEntities: SyncEntityRepositories
        let manager: LocalToRemoteSyncManager
    }

    private func makeEnvironment(
        local: SwiftDataTestHarness? = nil
    ) throws -> Environment {
        let harness = try local ?? SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let auth = FakeFirebaseAuthService()
        auth.setUID(DomainFixtures.technicianUser().id.rawValue)
        let localEntities = SyncEntityRepositories(
            users: harness.users,
            customers: harness.customers,
            workOrders: harness.workOrders,
            notes: harness.notes,
            photos: harness.photos,
            locations: harness.locations,
            statusHistory: harness.statusHistory,
            signatures: harness.signatures,
            editRequests: harness.editRequests,
            customerSatisfactions: harness.customerSatisfactions,
            notifications: harness.notifications
        )
        let manager = LocalToRemoteSyncManager(
            queue: harness.syncOperations,
            conflicts: harness.syncConflicts,
            local: localEntities,
            remote: remote.repositories,
            reachability: FakeNetworkReachability(),
            storage: FakeFirebaseStorageDataSource(),
            authService: auth
        )
        return Environment(
            local: harness,
            queue: harness.syncOperations,
            probe: probe,
            remoteWorkOrders: remote.workOrders,
            remoteEntities: remote.repositories,
            manager: manager
        )
    }

    private func makeService(
        local: SwiftDataTestHarness,
        queue: SyncOperationRepository
    ) -> TechnicianWorkOrderService {
        TechnicianWorkOrderService(
            updateStatus: UpdateWorkOrderStatusUseCase(
                workOrderRepository: local.workOrders,
                statusHistoryRepository: local.statusHistory
            ),
            completeWorkOrder: CompleteWorkOrderUseCase(
                workOrderRepository: local.workOrders,
                statusHistoryRepository: local.statusHistory,
                noteRepository: local.notes,
                photoRepository: local.photos,
                locationRepository: local.locations,
                signatureRepository: local.signatures
            ),
            addNoteUseCase: AddWorkOrderNoteUseCase(
                workOrderRepository: local.workOrders,
                noteRepository: local.notes
            ),
            addPhotoUseCase: AddWorkOrderPhotoUseCase(
                workOrderRepository: local.workOrders,
                photoRepository: local.photos
            ),
            captureLocationUseCase: CaptureWorkOrderLocationUseCase(
                workOrderRepository: local.workOrders,
                locationRepository: local.locations
            ),
            captureSignatureUseCase: CaptureSignatureUseCase(
                workOrderRepository: local.workOrders,
                signatureRepository: local.signatures
            ),
            statusHistoryRepository: local.statusHistory,
            customerSatisfactionService: TechnicianCustomerSatisfactionService(
                createCustomerSatisfaction: CreateCustomerSatisfactionUseCase(
                    workOrderRepository: local.workOrders,
                    customerSatisfactionRepository: local.customerSatisfactions
                ),
                syncOperationRepository: queue,
                workOrderRepository: local.workOrders,
                customerRepository: local.customers
            ),
            syncOperationRepository: queue,
            storageDataSource: FakeFirebaseStorageDataSource(),
            networkReachability: FakeNetworkReachability(isReachable: true)
        )
    }

    private func seedCompletableOrder(
        local: SwiftDataTestHarness,
        tech: User,
        remoteWorkOrders: InMemoryWorkOrderRepository
    ) async throws -> WorkOrder {
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            workType: .installation,
            status: .inProgress
        )
        try await local.users.save(tech)
        try await local.customers.save(customer)
        try await local.workOrders.save(order)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(order, on: remoteWorkOrders)

        let context = DomainFixtures.fullCompletionContext(for: .installation)
        for note in context.notes {
            try await local.notes.save(
                DomainFixtures.note(id: note.id, workOrderId: order.id, authorUserId: tech.id)
            )
        }
        for (index, photo) in context.photos.enumerated() {
            try await local.photos.save(
                DomainFixtures.photo(
                    id: "photo-\(index)",
                    workOrderId: order.id,
                    category: photo.category,
                    capturedByUserId: tech.id
                )
            )
        }
        for event in [LocationEvent.enRoute, .arrived] {
            try await local.locations.save(
                DomainFixtures.location(
                    id: "loc-\(event.rawValue)",
                    workOrderId: order.id,
                    event: event,
                    capturedByUserId: tech.id
                )
            )
        }
        try await local.signatures.save(
            DomainFixtures.signature(
                id: "sig-tech",
                workOrderId: order.id,
                kind: .technician,
                capturedByUserId: tech.id
            )
        )
        try await local.signatures.save(
            DomainFixtures.signature(
                id: "sig-cust",
                workOrderId: order.id,
                kind: .customer,
                signerName: "Müşteri",
                capturedByUserId: tech.id
            )
        )
        return order
    }

    private func awaitCustomerSatisfaction(
        local: SwiftDataTestHarness,
        orderId: WorkOrderID,
        timeoutMs: Int = 500
    ) async throws -> CustomerSatisfaction {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            let list = try await local.customerSatisfactions.list(for: orderId)
            if let first = list.first {
                return first
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("customer satisfaction not created for \(orderId.rawValue)")
        throw DomainError.notFound(entity: "CustomerSatisfaction", id: orderId.rawValue)
    }
}
