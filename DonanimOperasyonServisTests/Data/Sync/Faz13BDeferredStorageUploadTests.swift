import XCTest
@testable import DonanimOperasyonServis

/// Faz 13B — offline photo/signature bytes must upload to Firebase Storage
/// during real sync drain before Firestore metadata is accepted.
///
/// Capture uses a failing Storage fake (`pending://`); drain uses a working
/// Storage instance wired into `LocalToRemoteSyncManager`. Tests never
/// short-circuit enqueue/drain by pretending upload already succeeded.
final class Faz13BDeferredStorageUploadTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    // MARK: - Happy path

    func testOfflinePhotoUploadsOnSyncDrainAndClearsPendingPath() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let imageData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let photoId = "photo-deferred-1"
        let expectedPath = FirebaseStoragePath.photo(
            workOrderId: order.id,
            photoId: photoId
        )

        await env.captureStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )
        let service = makeTechnicianService(
            local: env.local,
            queue: env.queue,
            storage: env.captureStorage
        )
        let photo = try await service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: imageData,
            photoId: photoId,
            at: now
        )

        XCTAssertTrue(PendingStoragePath.isPending(photo.storagePath))
        XCTAssertEqual(
            TechnicianLocalMediaStore.loadPhoto(workOrderId: order.id, photoId: photoId),
            imageData
        )
        let beforeContains = await env.drainStorage.contains(expectedPath)
        XCTAssertFalse(beforeContains)

        let outcome = try await env.manager.syncPending(now: now)
        XCTAssertEqual(outcome, .completed)

        let localPhoto = try await env.local.photos.list(for: order.id).first { $0.id == photoId }
        XCTAssertEqual(localPhoto?.storagePath, expectedPath.rawValue)
        XCTAssertFalse(PendingStoragePath.isPending(localPhoto?.storagePath))

        let afterContains = await env.drainStorage.contains(expectedPath)
        let uploadedBlob = await env.drainStorage.blob(at: expectedPath)
        let uploadCount = await env.drainStorage.uploadCallCount
        XCTAssertTrue(afterContains)
        XCTAssertEqual(uploadedBlob, imageData)
        XCTAssertEqual(uploadCount, 1)

        let remotePhotos = try await env.remotePhotos.list(for: order.id)
        let remotePhoto = try XCTUnwrap(remotePhotos.first { $0.id == photoId })
        XCTAssertEqual(remotePhoto.storagePath, expectedPath.rawValue)
        XCTAssertFalse(PendingStoragePath.isPending(remotePhoto.storagePath))

        let ops = try await env.queue.list(entityType: .workOrderPhoto, entityId: photoId)
        XCTAssertTrue(ops.isEmpty, "succeeded photo row should be pruned after drain")
    }

    func testOfflineSignatureUploadsOnSyncDrainAndClearsPendingPath() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let imageData = TechnicianPlaceholderImage.pngData
        let signatureId = "sig-deferred-1"
        let expectedPath = FirebaseStoragePath.signature(
            workOrderId: order.id,
            signatureId: signatureId
        )

        await env.captureStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )
        let service = makeTechnicianService(
            local: env.local,
            queue: env.queue,
            storage: env.captureStorage
        )
        let signature = try await service.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: imageData,
            signatureId: signatureId,
            at: now
        )

        XCTAssertTrue(PendingStoragePath.isPending(signature.storagePath))
        XCTAssertEqual(
            TechnicianLocalMediaStore.loadSignature(
                workOrderId: order.id,
                signatureId: signatureId
            ),
            imageData
        )

        _ = try await env.manager.syncPending(now: now)

        let localSig = try await env.local.signatures.list(for: order.id)
            .first { $0.id == signatureId }
        XCTAssertEqual(localSig?.storagePath, expectedPath.rawValue)
        XCTAssertFalse(PendingStoragePath.isPending(localSig?.storagePath))

        let uploadedBlob = await env.drainStorage.blob(at: expectedPath)
        XCTAssertEqual(uploadedBlob, imageData)

        let remoteSigOptional = try await env.remoteSignatures.list(for: order.id)
            .first { $0.id == signatureId }
        let remoteSig = try XCTUnwrap(remoteSigOptional)
        XCTAssertEqual(remoteSig.storagePath, expectedPath.rawValue)

        let ops = try await env.queue.list(entityType: .signature, entityId: signatureId)
        XCTAssertTrue(ops.isEmpty, "succeeded signature row should be pruned after drain")
    }

    // MARK: - Failure / retry

    func testStorageUploadFailureKeepsPendingAndDoesNotWriteRemoteMetadata() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let photoId = "photo-fail-1"
        let expectedPath = FirebaseStoragePath.photo(
            workOrderId: order.id,
            photoId: photoId
        )
        let imageData = Data([0x01, 0x02])

        await env.captureStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )
        await env.drainStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )

        let service = makeTechnicianService(
            local: env.local,
            queue: env.queue,
            storage: env.captureStorage
        )
        _ = try await service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .after,
            imageData: imageData,
            photoId: photoId,
            at: now
        )

        _ = try await env.manager.syncPending(now: now)

        let localPhotoOptional = try await env.local.photos.list(for: order.id)
            .first { $0.id == photoId }
        let localPhoto = try XCTUnwrap(localPhotoOptional)
        XCTAssertTrue(PendingStoragePath.isPending(localPhoto.storagePath))
        XCTAssertEqual(
            TechnicianLocalMediaStore.loadPhoto(workOrderId: order.id, photoId: photoId),
            imageData
        )
        let contains = await env.drainStorage.contains(expectedPath)
        XCTAssertFalse(contains)

        let remotePhotos = try await env.remotePhotos.list(for: order.id)
        XCTAssertTrue(remotePhotos.isEmpty)

        let writes = await env.probe.recordedWrites()
        XCTAssertFalse(writes.contains(.save(.workOrderPhoto, photoId)))

        let ops = try await env.queue.list(entityType: .workOrderPhoto, entityId: photoId)
        let op = try XCTUnwrap(ops.first)
        XCTAssertEqual(op.status, .failed)
        XCTAssertEqual(op.retryCount, 1)
        XCTAssertNotNil(op.nextRetryAt)
        XCTAssertEqual(op.errorMessage, SyncError.serverError.diagnosticMessage)
    }

    func testFailedDeferredUploadRetriesSuccessfully() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let photoId = "photo-retry-1"
        let expectedPath = FirebaseStoragePath.photo(
            workOrderId: order.id,
            photoId: photoId
        )
        let imageData = Data([0xAA])

        await env.captureStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )
        await env.drainStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )

        let service = makeTechnicianService(
            local: env.local,
            queue: env.queue,
            storage: env.captureStorage
        )
        _ = try await service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: imageData,
            photoId: photoId,
            at: now
        )

        _ = try await env.manager.syncPending(now: now)
        let failedOptional = try await env.queue.list(
            entityType: .workOrderPhoto,
            entityId: photoId
        ).first
        let failed = try XCTUnwrap(failedOptional)
        XCTAssertEqual(failed.status, .failed)
        let retryAt = try XCTUnwrap(failed.nextRetryAt)

        await env.drainStorage.setUploadError(nil)
        _ = try await env.manager.syncPending(now: retryAt)

        let localPhotoOptional = try await env.local.photos.list(for: order.id)
            .first { $0.id == photoId }
        let localPhoto = try XCTUnwrap(localPhotoOptional)
        XCTAssertEqual(localPhoto.storagePath, expectedPath.rawValue)
        let uploadedBlob = await env.drainStorage.blob(at: expectedPath)
        XCTAssertEqual(uploadedBlob, imageData)

        let remotePhotoOptional = try await env.remotePhotos.list(for: order.id)
            .first { $0.id == photoId }
        let remotePhoto = try XCTUnwrap(remotePhotoOptional)
        XCTAssertEqual(remotePhoto.storagePath, expectedPath.rawValue)

        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: failed.id))
    }

    // MARK: - Idempotency / persistence

    func testAlreadyResolvedPathSkipsReUploadOnDrain() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let photoId = "photo-already-remote"
        let path = FirebaseStoragePath.photo(workOrderId: order.id, photoId: photoId)
        let imageData = Data([0x11, 0x22])

        // Capture succeeds immediately → real path (no deferred upload needed).
        let service = makeTechnicianService(
            local: env.local,
            queue: env.queue,
            storage: env.drainStorage
        )
        _ = try await service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: imageData,
            photoId: photoId,
            at: now
        )
        let afterCaptureUploads = await env.drainStorage.uploadCallCount
        XCTAssertEqual(afterCaptureUploads, 1)

        _ = try await env.manager.syncPending(now: now)

        let afterDrainUploads = await env.drainStorage.uploadCallCount
        XCTAssertEqual(afterDrainUploads, 1)
        let ops = try await env.queue.list(entityType: .workOrderPhoto, entityId: photoId)
        XCTAssertTrue(ops.isEmpty, "succeeded photo row should be pruned after drain")
        let remotePath = try await env.remotePhotos.list(for: order.id).first?.storagePath
        XCTAssertEqual(remotePath, path.rawValue)
    }

    func testRemoteMetadataFailureAfterUploadRetriesWithoutDuplicateUpload() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let photoId = "photo-idempotent"
        let expectedPath = FirebaseStoragePath.photo(
            workOrderId: order.id,
            photoId: photoId
        )
        let imageData = Data([0x55])

        await env.captureStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )
        let service = makeTechnicianService(
            local: env.local,
            queue: env.queue,
            storage: env.captureStorage
        )
        _ = try await service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: imageData,
            photoId: photoId,
            at: now
        )

        await env.probe.setError(.infrastructure(underlying: "firebase.serverError"))
        _ = try await env.manager.syncPending(now: now)

        let uploadsAfterFail = await env.drainStorage.uploadCallCount
        let containsAfterFail = await env.drainStorage.contains(expectedPath)
        XCTAssertEqual(uploadsAfterFail, 1)
        XCTAssertTrue(containsAfterFail)
        let afterUploadOptional = try await env.local.photos.list(for: order.id)
            .first { $0.id == photoId }
        let afterUpload = try XCTUnwrap(afterUploadOptional)
        XCTAssertEqual(afterUpload.storagePath, expectedPath.rawValue)
        let remoteEmpty = try await env.remotePhotos.list(for: order.id).isEmpty
        XCTAssertTrue(remoteEmpty)

        let failedOptional = try await env.queue.list(
            entityType: .workOrderPhoto,
            entityId: photoId
        ).first
        let failed = try XCTUnwrap(failedOptional)
        let retryAt = try XCTUnwrap(failed.nextRetryAt)

        await env.probe.setError(nil)
        _ = try await env.manager.syncPending(now: retryAt)

        // Path already real → deferred upload skipped; only remote metadata retries.
        let uploadsAfterRetry = await env.drainStorage.uploadCallCount
        XCTAssertEqual(uploadsAfterRetry, 1)
        let remoteOptional = try await env.remotePhotos.list(for: order.id)
            .first { $0.id == photoId }
        let remote = try XCTUnwrap(remoteOptional)
        XCTAssertEqual(remote.storagePath, expectedPath.rawValue)
        await XCTAssertThrowsErrorAsync(try await env.queue.fetch(id: failed.id))
    }

    func testPendingMediaSurvivesNewManagerInstanceLikeAppRelaunch() async throws {
        let local = try SwiftDataTestHarness()
        let captureStorage = FakeFirebaseStorageDataSource()
        await captureStorage.setUploadError(
            DomainError.infrastructure(underlying: "firebase.storageError")
        )

        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await local.users.save(tech)
        try await local.workOrders.save(order)

        let photoId = "photo-relaunch"
        let imageData = Data([0x99])
        let expectedPath = FirebaseStoragePath.photo(
            workOrderId: order.id,
            photoId: photoId
        )

        let service = makeTechnicianService(
            local: local,
            queue: local.syncOperations,
            storage: captureStorage
        )
        _ = try await service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: imageData,
            photoId: photoId,
            at: now
        )

        // Simulate process death: new drain Storage + new sync manager, same local SoT + disk.
        let drainStorage = FakeFirebaseStorageDataSource()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let auth = FakeFirebaseAuthService()
        auth.setUID(DomainFixtures.technicianUser().id.rawValue)
        try await remote.workOrders.save(order)
        let manager = LocalToRemoteSyncManager(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: SyncEntityRepositories(
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
            ),
            remote: remote.repositories,
            reachability: FakeNetworkReachability(),
            storage: drainStorage,
            authService: auth
        )

        XCTAssertEqual(
            TechnicianLocalMediaStore.loadPhoto(workOrderId: order.id, photoId: photoId),
            imageData
        )
        _ = try await manager.syncPending(now: now)

        let localPath = try await local.photos.list(for: order.id).first?.storagePath
        XCTAssertEqual(localPath, expectedPath.rawValue)
        let uploadedBlob = await drainStorage.blob(at: expectedPath)
        XCTAssertEqual(uploadedBlob, imageData)
        let remotePath = try await remote.photos.list(for: order.id).first?.storagePath
        XCTAssertEqual(remotePath, expectedPath.rawValue)
    }

    func testMissingLocalBytesFailsWithoutRemotePendingWrite() async throws {
        let env = try await makeEnvironment()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let photoId = "photo-missing-bytes"
        let path = FirebaseStoragePath.photo(workOrderId: order.id, photoId: photoId)
        var photo = DomainFixtures.photo(
            id: photoId,
            workOrderId: order.id,
            category: .before
        )
        photo.storagePath = PendingStoragePath.wrap(path.rawValue)
        try await env.local.photos.save(photo)

        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-missing-bytes"),
            entityType: .workOrderPhoto,
            entityId: photoId,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1
        )
        _ = try await env.queue.enqueue(operation)

        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .failed)
        XCTAssertEqual(stored.errorMessage, SyncError.invalidPayload.diagnosticMessage)
        XCTAssertNil(stored.nextRetryAt)
        let remoteEmpty = try await env.remotePhotos.list(for: order.id).isEmpty
        XCTAssertTrue(remoteEmpty)
        let stillPending = PendingStoragePath.isPending(
            try await env.local.photos.list(for: order.id).first?.storagePath
        )
        XCTAssertTrue(stillPending)
    }

    // MARK: - Helpers

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let probe: SyncRemoteProbe
        let captureStorage: FakeFirebaseStorageDataSource
        let drainStorage: FakeFirebaseStorageDataSource
        let remotePhotos: InMemoryPhotoRepository
        let remoteSignatures: InMemorySignatureRepository
        let manager: LocalToRemoteSyncManager
    }

    private func makeEnvironment() async throws -> Environment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let captureStorage = FakeFirebaseStorageDataSource()
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
        let defaultOrder = DomainFixtures.workOrder(
            assignedTechnicianId: DomainFixtures.technicianUser().id,
            status: .inProgress
        )
        try await remote.workOrders.save(defaultOrder)
        return Environment(
            local: local,
            queue: local.syncOperations,
            probe: probe,
            captureStorage: captureStorage,
            drainStorage: drainStorage,
            remotePhotos: remote.photos,
            remoteSignatures: remote.signatures,
            manager: manager
        )
    }

    private func makeTechnicianService(
        local: SwiftDataTestHarness,
        queue: SyncOperationRepository,
        storage: FakeFirebaseStorageDataSource
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
            storageDataSource: storage
        )
    }
}
