import XCTest
@testable import DonanimOperasyonServis

/// Faz 13A — child sync must carry `payloadReference` = parent work-order id
/// via the **real** application enqueue path (`TechnicianWorkOrderService` /
/// `OperatorWorkOrderService` / `TechnicianSyncEnqueue`), not hand-built ops
/// that previously masked the bug.
final class Faz13AChildSyncPayloadReferenceTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    func testTechnicianEnqueueSetsPayloadReferenceForAllChildren() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)
        let parent = order.id.rawValue

        let note = try await deps.workOrderService.addNote(
            actor: tech, orderId: order.id, text: "Not"
        )
        let photo = try await deps.workOrderService.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: Data([0x01, 0x02])
        )
        let location = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .arrived,
            coordinate: LocationCoordinate(latitude: 41, longitude: 29, accuracy: 5)
        )
        let signature = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: TechnicianPlaceholderImage.pngData
        )
        _ = try await deps.workOrderService.transitionStatus(
            actor: tech,
            orderId: order.id,
            newStatus: .paused,
            pauseReason: .partWaiting
        )

        try await assertPayload(deps.syncOperationRepository, type: .workOrderNote, id: note.id, parent: parent)
        try await assertPayload(deps.syncOperationRepository, type: .workOrderPhoto, id: photo.id, parent: parent)
        try await assertPayload(deps.syncOperationRepository, type: .workOrderLocation, id: location.id, parent: parent)
        try await assertPayload(deps.syncOperationRepository, type: .signature, id: signature.id, parent: parent)

        let history = try await deps.statusHistoryRepository.list(for: order.id)
        let latest = try XCTUnwrap(history.last)
        try await assertPayload(
            deps.syncOperationRepository,
            type: .workOrderStatusHistory,
            id: latest.id,
            parent: parent
        )
    }

    func testOperatorCreateInitialHistoryCarriesPayloadReference() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        try await container.userRepository.save(technician)
        try await container.userRepository.save(operatorUser)

        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: DomainFixtures.newWorkOrderRequest(
                assignedTechnicianId: technician.id,
                customerId: customer.id
            )
        )
        let history = try await deps.statusHistoryRepository.list(for: created.id)
        let initial = try XCTUnwrap(history.first)
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderStatusHistory,
            entityId: initial.id
        )
        XCTAssertEqual(ops.first?.payloadReference, created.id.rawValue)
        XCTAssertEqual(ops.first?.status, .pending)
    }

    func testAppEnqueuedChildrenSyncToRemoteSuccessfully() async throws {
        let env = try makeSyncEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(order, on: env.remoteWorkOrders)

        let service = makeTechnicianService(local: env.local, queue: env.queue)

        let note = try await service.addNote(actor: tech, orderId: order.id, text: "Sync note")
        let photo = try await service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .after,
            imageData: Data([0xAA])
        )
        let location = try await service.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .enRoute,
            coordinate: LocationCoordinate(latitude: 40, longitude: 28, accuracy: 3)
        )
        let signature = try await service.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .customer,
            imageData: TechnicianPlaceholderImage.pngData,
            signerName: "Müşteri"
        )

        _ = try await env.manager.syncPending(now: now)

        for (type, id) in [
            (SyncEntityType.workOrderNote, note.id),
            (.workOrderPhoto, photo.id),
            (.workOrderLocation, location.id),
            (.signature, signature.id)
        ] {
            let ops = try await env.queue.list(entityType: type, entityId: id)
            XCTAssertTrue(ops.isEmpty, "\(type.rawValue) succeeded row should be pruned")
        }

        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.contains(.save(.workOrderNote, note.id)))
        XCTAssertTrue(writes.contains(.save(.workOrderPhoto, photo.id)))
        XCTAssertTrue(writes.contains(.save(.workOrderLocation, location.id)))
        XCTAssertTrue(writes.contains(.save(.signature, signature.id)))
    }

    func testMissingPayloadReferenceFailsAtEnqueue() async throws {
        let harness = try SwiftDataTestHarness()
        do {
            try await TechnicianSyncEnqueue.enqueueCreate(
                entityType: .workOrderNote,
                entityId: "note-x",
                queue: harness.syncOperations,
                now: now,
                actorUserId: "test-tech"
            )
            XCTFail("expected invalidPayload")
        } catch {
            XCTAssertEqual(error as? SyncError, .invalidPayload)
        }
        let listed = try await harness.syncOperations.list(
            entityType: .workOrderNote,
            entityId: "note-x"
        )
        XCTAssertTrue(listed.isEmpty)
    }

    func testWrongParentPayloadReferenceFailsDispatchTerminally() async throws {
        let env = try makeSyncEnvironment()
        let order = DomainFixtures.workOrder(status: .inProgress)
        let note = DomainFixtures.note(workOrderId: order.id)
        let otherParent = DomainFixtures.workOrder(
            id: WorkOrderID("wo-other-parent"),
            status: .inProgress
        )
        try await env.local.workOrders.save(order)
        try await env.local.notes.save(note)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(otherParent, on: env.remoteWorkOrders)

        // Payload points at a different parent → local list miss → notFound
        // (terminal; no nextRetryAt).
        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-wrong-parent"),
            entityType: .workOrderNote,
            entityId: note.id,
            operationType: .create,
            payloadReference: "wo-other-parent",
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.retryCount, 1)
        XCTAssertEqual(stored.payloadReference, "wo-other-parent")
        XCTAssertNil(stored.nextRetryAt)
        XCTAssertEqual(stored.errorMessage, SyncError.notFound.diagnosticMessage)
    }

    func testDuplicateEnqueueGetsDistinctVersionsWithSamePayloadReference() async throws {
        let harness = try SwiftDataTestHarness()
        let parent = "wo-dup"

        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .workOrderLocation,
            entityId: "loc-1",
            queue: harness.syncOperations,
            now: now,
            actorUserId: "test-tech",
            payloadReference: parent
        )
        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .workOrderLocation,
            entityId: "loc-1",
            queue: harness.syncOperations,
            now: now.addingTimeInterval(1),
            actorUserId: "test-tech",
            payloadReference: parent
        )

        let ops = try await harness.syncOperations.list(
            entityType: .workOrderLocation,
            entityId: "loc-1"
        )
        XCTAssertEqual(ops.count, 2)
        XCTAssertEqual(Set(ops.map(\.payloadReference)), [parent])
        XCTAssertEqual(Set(ops.map(\.localVersion)).count, 2)
    }

    func testRetryPreservesPayloadReference() async throws {
        let env = try makeSyncEnvironment()
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))

        let order = DomainFixtures.workOrder(status: .inProgress)
        let note = DomainFixtures.note(workOrderId: order.id)
        try await env.local.workOrders.save(order)
        try await env.local.notes.save(note)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(order, on: env.remoteWorkOrders)

        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-retry"),
            entityType: .workOrderNote,
            entityId: note.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let failed = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.payloadReference, order.id.rawValue)
        XCTAssertEqual(failed.retryCount, 1)

        await env.probe.setError(nil)
        try await env.manager.sync(operation: failed, now: now.addingTimeInterval(10))

        let succeeded = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(succeeded.status, .succeeded)
        XCTAssertEqual(succeeded.payloadReference, order.id.rawValue)
    }

    // MARK: - Helpers

    private func assertPayload(
        _ queue: SyncOperationRepository,
        type: SyncEntityType,
        id: String,
        parent: String
    ) async throws {
        let ops = try await queue.list(entityType: type, entityId: id)
        let op = try XCTUnwrap(ops.first)
        XCTAssertEqual(op.payloadReference, parent, type.rawValue)
        XCTAssertEqual(op.operationType, .create)
    }

    private func seedInProgressOrder(
        deps: TechnicianDependencies,
        container: DIContainer,
        tech: User
    ) async throws -> WorkOrder {
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await deps.customerRepository.save(customer)
        try await container.userRepository.save(tech)
        try await container.workOrderRepository.save(order)
        return order
    }

    private struct SyncEnvironment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let probe: SyncRemoteProbe
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let manager: LocalToRemoteSyncManager
    }

    private func makeSyncEnvironment() throws -> SyncEnvironment {
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
        let storage = FakeFirebaseStorageDataSource()
        let manager = LocalToRemoteSyncManager(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: localEntities,
            remote: remote.repositories,
            reachability: FakeNetworkReachability(),
            storage: storage,
            authService: auth
        )
        return SyncEnvironment(
            local: local,
            queue: local.syncOperations,
            probe: probe,
            remoteWorkOrders: remote.workOrders,
            manager: manager
        )
    }

    private func makeTechnicianService(
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
            storageDataSource: FakeFirebaseStorageDataSource()
        )
    }
}
