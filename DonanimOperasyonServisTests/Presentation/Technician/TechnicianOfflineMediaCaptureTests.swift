import XCTest
@testable import DonanimOperasyonServis

/// Regression: unreachable devices must not attempt Firebase Storage upload
/// during field capture; media is saved locally with a pending storage path.
@MainActor
final class TechnicianOfflineMediaCaptureTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    func testOfflineSignatureSkipsStorageUploadAndEnqueuesPendingSync() async throws {
        let env = try await makeEnvironment(isReachable: false)
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let imageData = TechnicianPlaceholderImage.pngData
        let signatureId = "sig-offline-1"
        let expectedPath = FirebaseStoragePath.signature(
            workOrderId: order.id,
            signatureId: signatureId
        )

        let signature = try await env.service.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: imageData,
            signatureId: signatureId,
            at: now
        )

        let uploadCount = await env.storage.uploadCallCount
        XCTAssertEqual(uploadCount, 0)

        XCTAssertTrue(PendingStoragePath.isPending(signature.storagePath))
        XCTAssertEqual(
            signature.storagePath,
            PendingStoragePath.wrap(expectedPath.rawValue)
        )
        XCTAssertEqual(
            TechnicianLocalMediaStore.loadSignature(
                workOrderId: order.id,
                signatureId: signatureId
            ),
            imageData
        )

        let stored = try await env.local.signatures.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, signatureId)

        let ops = try await env.queue.list(entityType: .signature, entityId: signatureId)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.operationType, .create)
        XCTAssertEqual(ops.first?.status, .pending)
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testOfflinePhotoSkipsStorageUploadAndEnqueuesPendingSync() async throws {
        let env = try await makeEnvironment(isReachable: false)
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let imageData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let photoId = "photo-offline-1"
        let expectedPath = FirebaseStoragePath.photo(
            workOrderId: order.id,
            photoId: photoId
        )

        let photo = try await env.service.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: imageData,
            photoId: photoId,
            at: now
        )

        let uploadCount = await env.storage.uploadCallCount
        XCTAssertEqual(uploadCount, 0)

        XCTAssertTrue(PendingStoragePath.isPending(photo.storagePath))
        XCTAssertEqual(
            photo.storagePath,
            PendingStoragePath.wrap(expectedPath.rawValue)
        )
        XCTAssertEqual(
            TechnicianLocalMediaStore.loadPhoto(workOrderId: order.id, photoId: photoId),
            imageData
        )

        let stored = try await env.local.photos.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, photoId)

        let ops = try await env.queue.list(entityType: .workOrderPhoto, entityId: photoId)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.operationType, .create)
        XCTAssertEqual(ops.first?.status, .pending)
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testOnlineSignatureStillAttemptsStorageUpload() async throws {
        let env = try await makeEnvironment(isReachable: true)
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)

        let imageData = TechnicianPlaceholderImage.pngData
        let signature = try await env.service.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: imageData,
            at: now
        )

        let uploadCount = await env.storage.uploadCallCount
        XCTAssertEqual(uploadCount, 1)
        XCTAssertFalse(PendingStoragePath.isPending(signature.storagePath))
    }

    // MARK: - Helpers

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SyncOperationRepository
        let storage: FakeFirebaseStorageDataSource
        let service: TechnicianWorkOrderService
    }

    private func makeEnvironment(isReachable: Bool) async throws -> Environment {
        let local = try SwiftDataTestHarness()
        let storage = FakeFirebaseStorageDataSource()
        let queue = local.syncOperations
        let reachability = FakeNetworkReachability(isReachable: isReachable)
        let service = TechnicianWorkOrderService(
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
            storageDataSource: storage,
            networkReachability: reachability
        )
        return Environment(
            local: local,
            queue: queue,
            storage: storage,
            service: service
        )
    }
}
