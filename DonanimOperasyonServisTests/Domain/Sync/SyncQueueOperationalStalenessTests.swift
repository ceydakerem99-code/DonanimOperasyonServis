import XCTest
@testable import DonanimOperasyonServis

final class SyncQueueOperationalStalenessTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    func testCompletedWorkOrderIgnoresFailedUpdateForDetailBanner() {
        let failed = makeWorkOrderUpdate(status: .failed, entityId: "wo-1")
        XCTAssertFalse(
            SyncQueueOperationalStaleness.isDetailBlocking(failed, workOrderStatus: .completed)
        )
        XCTAssertTrue(
            SyncQueueOperationalStaleness.isDetailBlocking(failed, workOrderStatus: .inProgress)
        )
    }

    func testCompletedWorkOrderStillShowsPendingUpdateForDetailBanner() {
        let pending = makeWorkOrderUpdate(status: .pending, entityId: "wo-1")
        XCTAssertTrue(
            SyncQueueOperationalStaleness.isDetailBlocking(pending, workOrderStatus: .completed)
        )
    }

    func testCompletedWorkOrderIgnoresSupersededPendingStatusUpdateForDetailBanner() async throws {
        let container = DIContainer.mock()
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-1"),
            status: .completed
        )
        try await container.workOrderRepository.save(order)

        let stalePending = try SyncOperation.pending(
            id: SyncOperationID("op-stale"),
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 1,
            workOrderStatus: .inProgress,
            actorUserId: DomainFixtures.technicianUser().id.rawValue
        )
        _ = try await container.syncOperationRepository.enqueue(stalePending)

        XCTAssertFalse(
            try await SyncQueueOperationalStaleness.isWorkOrderOperationDetailBlocking(
                stalePending,
                workOrder: order,
                queue: container.syncOperationRepository
            )
        )
    }

    func testCompletedWorkOrderIgnoresStalePendingStoragePathWithoutOpenCreate() async throws {
        let container = DIContainer.mock()
        let order = DomainFixtures.workOrder(status: .completed)
        try await container.workOrderRepository.save(order)

        let photo = WorkOrderPhoto(
            id: "photo-stale",
            workOrderId: order.id,
            category: .before,
            storagePath: PendingStoragePath.wrap("workOrders/\(order.id.rawValue)/photos/p1"),
            capturedByUserId: DomainFixtures.technicianUser().id,
            capturedAt: now
        )
        try await container.workOrderPhotoRepository.save(photo)

        XCTAssertFalse(
            try await SyncQueueOperationalStaleness.isMediaUploadDetailBlocking(
                hasPendingStoragePath: photo.isUploadPending,
                entityType: .workOrderPhoto,
                entityId: photo.id,
                workOrder: order,
                queue: container.syncOperationRepository
            )
        )
    }

    func testIrrelevantFailedCustomerSatisfactionIsPrunedWhenParentCompleted() async throws {
        let container = DIContainer.mock()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: technician.id,
            customerId: customer.id,
            status: .completed
        )
        try await container.userRepository.save(technician)
        try await container.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let satisfaction = CustomerSatisfaction(
            id: CustomerSatisfactionID("cs-1"),
            workOrderId: order.id,
            customerId: customer.id,
            status: .pending,
            createdAt: now,
            updatedAt: now
        )
        try await container.customerSatisfactionRepository.save(satisfaction)

        var failed = try SyncOperation.pending(
            id: SyncOperationID("cs-fail"),
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue,
            operationType: .create,
            createdAt: now,
            actorUserId: technician.id.rawValue
        )
        failed.status = .failed
        failed.errorMessage = SyncError.unauthorized.diagnosticMessage
        _ = try await container.syncOperationRepository.enqueue(failed)

        let local = SyncEntityRepositories(
            users: container.userRepository,
            customers: container.customerRepository,
            workOrders: container.workOrderRepository,
            notes: container.workOrderNoteRepository,
            photos: container.workOrderPhotoRepository,
            locations: container.workOrderLocationRepository,
            statusHistory: container.workOrderStatusHistoryRepository,
            signatures: container.signatureRepository,
            editRequests: container.editRequestRepository,
            customerSatisfactions: container.customerSatisfactionRepository,
            notifications: container.notificationRepository
        )

        let irrelevant = try await SyncQueueOperationalStaleness.irrelevantFailedIDs(
            failed: [failed],
            queue: container.syncOperationRepository,
            local: local
        )
        XCTAssertEqual(irrelevant, [failed.id])
    }

    private func makeWorkOrderUpdate(status: SyncStatus, entityId: String) -> SyncOperation {
        var operation = try! SyncOperation.pending(
            id: SyncOperationID(UUID().uuidString),
            entityType: .workOrder,
            entityId: entityId,
            operationType: .update,
            createdAt: now,
            localVersion: 2
        )
        operation.status = status
        if status == .failed {
            operation.errorMessage = SyncError.unauthorized.diagnosticMessage
        }
        return operation
    }
}
