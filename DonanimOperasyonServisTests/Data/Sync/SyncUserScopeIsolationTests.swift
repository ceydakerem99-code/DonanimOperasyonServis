import XCTest
@testable import DonanimOperasyonServis

/// Session isolation, drain-loop bounds, and offline media sync regressions.
final class SyncUserScopeIsolationTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    private static let ceydaOperatorID = UserID("operator-ceyda-sync-test")
    private static let mehmetTechnicianID = DomainFixtures.mehmetTechnicianUID

    // MARK: - User scope

    func testPendingOperationsAreUserScoped() async throws {
        let env = try await makeEnvironment(authUID: Self.ceydaOperatorID.rawValue)
        let ceyda = DomainFixtures.operatorUser(id: Self.ceydaOperatorID)
        let mehmet = DomainFixtures.mehmetTechnician()
        let order = DomainFixtures.workOrder(createdByUserId: ceyda.id)
        try await env.local.users.save(ceyda)
        try await env.local.users.save(mehmet)
        try await env.local.workOrders.save(order)

        let ceydaOp = try SyncOperation.pending(
            id: SyncOperationID("scoped-ceyda"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1,
            actorUserId: ceyda.id.rawValue
        )
        let mehmetOp = try SyncOperation.pending(
            id: SyncOperationID("scoped-mehmet"),
            entityType: .workOrderNote,
            entityId: "note-mehmet",
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now.addingTimeInterval(1),
            localVersion: 1,
            actorUserId: mehmet.id.rawValue
        )
        _ = try await env.queue.enqueue(ceydaOp)
        _ = try await env.queue.enqueue(mehmetOp)

        let allPending = try await env.queue.fetchPending(now: now)
        XCTAssertEqual(allPending.count, 2)

        let scoped = try await SyncOperationUserScope.filter(
            allPending,
            authUID: Self.ceydaOperatorID.rawValue,
            local: env.localEntities
        )
        XCTAssertEqual(scoped.map(\.id), [ceydaOp.id])
    }

    func testActorMismatchDoesNotDrainForWrongUser() async throws {
        let env = try await makeEnvironment(authUID: Self.mehmetTechnicianID.rawValue)
        let ceyda = DomainFixtures.operatorUser(id: Self.ceydaOperatorID)
        let order = DomainFixtures.workOrder(createdByUserId: ceyda.id)
        try await env.local.users.save(ceyda)
        try await env.local.workOrders.save(order)

        let create = try SyncOperation.pending(
            id: SyncOperationID("foreign-operator-wo"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1,
            actorUserId: ceyda.id.rawValue
        )
        _ = try await env.queue.enqueue(create)

        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: create.id)
        XCTAssertEqual(stored.status, .pending)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)

        env.auth.setUID(Self.ceydaOperatorID.rawValue)
        _ = try await env.manager.syncPending(now: now.addingTimeInterval(1))

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: create.id))
        let afterWrites = await env.probe.recordedWrites()
        XCTAssertTrue(afterWrites.contains(.save(.workOrder, order.id.rawValue)))
    }

    func testLegitimatePendingOperationRestoresForOwner() async throws {
        let env = try await makeEnvironment(authUID: Self.mehmetTechnicianID.rawValue)
        let mehmet = DomainFixtures.mehmetTechnician()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: mehmet.id,
            status: .inProgress
        )
        let note = DomainFixtures.note(
            workOrderId: order.id,
            authorUserId: mehmet.id
        )
        try await env.local.users.save(mehmet)
        try await env.local.workOrders.save(order)
        try await env.local.notes.save(note)
        try await env.remoteWorkOrders.save(order)

        let noteOp = try SyncOperation.pending(
            id: SyncOperationID("mehmet-note"),
            entityType: .workOrderNote,
            entityId: note.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: mehmet.id.rawValue
        )
        _ = try await env.queue.enqueue(noteOp)

        env.auth.setUID(Self.ceydaOperatorID.rawValue)
        _ = try await env.manager.syncPending(now: now)
        var stored = try await env.queue.fetch(id: noteOp.id)
        XCTAssertEqual(stored.status, .pending)

        env.auth.setUID(Self.mehmetTechnicianID.rawValue)
        _ = try await env.manager.syncPending(now: now.addingTimeInterval(1))
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: noteOp.id))
    }

    func testBackfillDoesNotAssignForeignOperationsToCurrentUser() async throws {
        let env = try await makeEnvironment(authUID: Self.mehmetTechnicianID.rawValue)
        let ceyda = DomainFixtures.operatorUser(id: Self.ceydaOperatorID)
        let order = DomainFixtures.workOrder(createdByUserId: ceyda.id)
        try await env.local.users.save(ceyda)
        try await env.local.workOrders.save(order)

        let create = try SyncOperation.pending(
            id: SyncOperationID("legacy-no-actor"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(create)

        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: create.id)
        XCTAssertEqual(stored.actorUserId, ceyda.id.rawValue)
        XCTAssertEqual(stored.status, .pending)
    }

    func testLogoutLoginPreservesUserQueueIsolation() async throws {
        try await testActorMismatchDoesNotDrainForWrongUser()
    }

    func testCeydaAndMehmetQueueIsolation() async throws {
        let env = try await makeEnvironment(authUID: Self.ceydaOperatorID.rawValue)
        let ceyda = DomainFixtures.operatorUser(id: Self.ceydaOperatorID)
        let mehmet = DomainFixtures.mehmetTechnician()
        let order = DomainFixtures.workOrder(
            createdByUserId: ceyda.id,
            assignedTechnicianId: mehmet.id,
            status: .inProgress
        )
        try await env.local.users.save(ceyda)
        try await env.local.users.save(mehmet)
        try await env.local.workOrders.save(order)

        let operatorUpdate = try SyncOperation.pending(
            id: SyncOperationID("ceyda-wo-update"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            actorUserId: ceyda.id.rawValue
        )
        let techPhoto = try SyncOperation.pending(
            id: SyncOperationID("mehmet-photo"),
            entityType: .workOrderPhoto,
            entityId: "photo-1",
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now.addingTimeInterval(1),
            localVersion: 1,
            actorUserId: mehmet.id.rawValue
        )
        _ = try await env.queue.enqueue(operatorUpdate)
        _ = try await env.queue.enqueue(techPhoto)

        env.auth.setUID(Self.mehmetTechnicianID.rawValue)
        _ = try await env.manager.syncPending(now: now)

        let operatorStored = try await env.queue.fetch(id: operatorUpdate.id)
        XCTAssertEqual(operatorStored.status, .pending)
        let mehmetStored = try await env.queue.fetch(id: techPhoto.id)
        XCTAssertEqual(mehmetStored.status, .pending)

        env.auth.setUID(Self.ceydaOperatorID.rawValue)
        _ = try await env.manager.syncPending(now: now.addingTimeInterval(2))
        let operatorAfter = try await env.queue.fetch(id: operatorUpdate.id)
        XCTAssertNotEqual(operatorAfter.status, .succeeded)
    }

    // MARK: - Drain loop

    func testAutoDrainDoesNotProcessSameOperationTwice() async throws {
        let env = try await makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
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

        let heldOp = try SyncOperation.pending(
            id: SyncOperationID("held-once"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(heldOp)

        _ = try await env.manager.syncPending(now: now)

        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.pendingAtStart, 1)
        XCTAssertEqual(report?.operations.count, 1)
        XCTAssertEqual(report?.held, 1)
    }

    func testAutoDrainTerminatesWithinQueueSnapshot() async throws {
        let env = try await makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
        let tech = DomainFixtures.technicianUser()
        try await env.local.users.save(tech)

        for index in 0..<5 {
            let order = DomainFixtures.workOrder(
                id: WorkOrderID("held-wo-\(index)"),
                workOrderNumber: "WO-HELD-\(index)",
                assignedTechnicianId: tech.id,
                status: .inProgress
            )
            let location = DomainFixtures.location(
                id: "loc-held-\(index)",
                workOrderId: order.id,
                event: .arrived,
                capturedByUserId: tech.id
            )
            try await env.local.workOrders.save(order)
            try await env.local.locations.save(location)
            let op = try SyncOperation.pending(
                id: SyncOperationID("held-op-\(index)"),
                entityType: .workOrderLocation,
                entityId: location.id,
                operationType: .create,
                payloadReference: order.id.rawValue,
                createdAt: now.addingTimeInterval(TimeInterval(index)),
                localVersion: 1,
                actorUserId: tech.id.rawValue
            )
            _ = try await env.queue.enqueue(op)
        }

        _ = try await env.manager.syncPending(now: now)

        let report = await env.manager.lastDrainReport()
        XCTAssertEqual(report?.pendingAtStart, 5)
        XCTAssertLessThanOrEqual(report?.operations.count ?? 0, 5)
    }

    // MARK: - Retry semantics

    func testRetryableFailureIsRetried() async throws {
        let env = try await makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
        await env.probe.setError(.infrastructure(underlying: "firebase.networkUnavailable"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try SyncOperation.pending(
            id: SyncOperationID("retryable"),
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)

        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertNotNil(stored.nextRetryAt)
    }

    func testPermanentFailureDoesNotLoopForever() async throws {
        let env = try await makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
        await env.probe.setError(.infrastructure(underlying: "firebase.permissionDenied"))
        let customer = DomainFixtures.customer()
        try await env.local.customers.save(customer)
        let operation = try SyncOperation.pending(
            id: SyncOperationID("permanent-unauth"),
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
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

    func testUnauthorizedWorkOrderUpdateUsesCorrectActor() async throws {
        let env = try await makeEnvironment(authUID: Self.mehmetTechnicianID.rawValue)
        let ceyda = DomainFixtures.operatorUser(id: Self.ceydaOperatorID)
        let mehmet = DomainFixtures.mehmetTechnician()
        let order = DomainFixtures.workOrder(
            createdByUserId: ceyda.id,
            assignedTechnicianId: mehmet.id,
            status: .inProgress
        )
        try await env.local.users.save(ceyda)
        try await env.local.users.save(mehmet)
        try await env.local.workOrders.save(order)
        try await env.remoteWorkOrders.save(order)

        await env.probe.setError(.infrastructure(underlying: "firebase.permissionDenied"))
        let operatorUpdate = try SyncOperation.pending(
            id: SyncOperationID("operator-unauth-update"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            actorUserId: ceyda.id.rawValue
        )
        _ = try await env.queue.enqueue(operatorUpdate)

        _ = try await env.manager.syncPending(now: now)

        let stored = try await env.queue.fetch(id: operatorUpdate.id)
        XCTAssertEqual(stored.status, .pending)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)

        env.auth.setUID(Self.ceydaOperatorID.rawValue)
        await env.probe.setError(nil)
        _ = try await env.manager.syncPending(now: now.addingTimeInterval(1))

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: operatorUpdate.id))
    }

    // MARK: - Photo / signature E2E (delegates to Faz13B harness)

    func testPhotoUploadSucceedsAfterOffline() async throws {
        let env = try await makeMediaEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await env.remoteWorkOrders.save(order)

        let imageData = Data([0x01, 0x02, 0x03])
        let photoId = "scoped-photo-1"
        let storagePath = PendingStoragePath.wrap(
            FirebaseStoragePath.photo(workOrderId: order.id, photoId: photoId).rawValue
        )
        _ = try TechnicianLocalMediaStore.savePhoto(
            data: imageData,
            workOrderId: order.id,
            photoId: photoId
        )
        var photo = DomainFixtures.photo(
            id: photoId,
            workOrderId: order.id,
            category: .before,
            capturedByUserId: tech.id
        )
        photo.storagePath = storagePath
        try await env.local.photos.save(photo)

        let op = try SyncOperation.pending(
            id: SyncOperationID("photo-op"),
            entityType: .workOrderPhoto,
            entityId: photoId,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(op)

        _ = try await env.manager.syncPending(now: now)

        let remotePhotos = try await env.remotePhotos.list(for: order.id)
        XCTAssertEqual(remotePhotos.count, 1)
        XCTAssertFalse(PendingStoragePath.isPending(remotePhotos.first?.storagePath))
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: op.id))
    }

    func testSignatureUploadSucceedsAfterOffline() async throws {
        let env = try await makeMediaEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await env.remoteWorkOrders.save(order)

        let signatureId = "scoped-sig-1"
        let storagePath = PendingStoragePath.wrap(
            FirebaseStoragePath.signature(workOrderId: order.id, signatureId: signatureId).rawValue
        )
        _ = try TechnicianLocalMediaStore.saveSignature(
            data: TechnicianPlaceholderImage.pngData,
            workOrderId: order.id,
            signatureId: signatureId
        )
        var signature = DomainFixtures.signature(
            id: signatureId,
            workOrderId: order.id,
            kind: .customer,
            capturedByUserId: tech.id
        )
        signature.storagePath = storagePath
        try await env.local.signatures.save(signature)

        let op = try SyncOperation.pending(
            id: SyncOperationID("sig-op"),
            entityType: .signature,
            entityId: signatureId,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(op)

        _ = try await env.manager.syncPending(now: now)

        let remoteSignatures = try await env.remoteSignatures.list(for: order.id)
        XCTAssertEqual(remoteSignatures.count, 1)
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: op.id))
    }

    func testMissingLocalMediaIsPermanentNotRetryable() throws {
        let error = SyncErrorMapping.from(
            DomainError.infrastructure(underlying: "firebase.storageError.localMediaMissing")
        )
        XCTAssertEqual(error, .invalidPayload)
        XCTAssertFalse(SyncRetryPolicy.isRetryable(error))
    }

    // MARK: - Helpers

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let localEntities: SyncEntityRepositories
        let probe: SyncRemoteProbe
        let manager: LocalToRemoteSyncManager
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let auth: FakeFirebaseAuthService
    }

    private struct MediaEnvironment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let manager: LocalToRemoteSyncManager
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let remotePhotos: InMemoryPhotoRepository
        let remoteSignatures: InMemorySignatureRepository
    }

    private func makeEnvironment(authUID: String) async throws -> Environment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let auth = FakeFirebaseAuthService()
        auth.setUID(authUID)
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
            localEntities: localEntities,
            probe: probe,
            manager: manager,
            remoteWorkOrders: remote.workOrders,
            auth: auth
        )
    }

    private func makeMediaEnvironment() async throws -> MediaEnvironment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let drainStorage = FakeFirebaseStorageDataSource()
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
            storage: drainStorage,
            authService: auth
        )
        return MediaEnvironment(
            local: local,
            queue: local.syncOperations,
            manager: manager,
            remoteWorkOrders: remote.workOrders,
            remotePhotos: remote.photos,
            remoteSignatures: remote.signatures
        )
    }
}
