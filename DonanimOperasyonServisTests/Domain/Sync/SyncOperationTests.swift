import XCTest
@testable import DonanimOperasyonServis

final class SyncOperationTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    func testPendingCreateHasInitialPendingStatus() throws {
        let op = try SyncOperation.pending(
            entityType: .customer,
            entityId: "cust-1",
            operationType: .create,
            payloadReference: "customers/cust-1",
            createdAt: now,
            localVersion: 1
        )
        XCTAssertEqual(op.status, .pending)
        XCTAssertEqual(op.retryCount, 0)
        XCTAssertNil(op.lastAttemptAt)
        XCTAssertNil(op.nextRetryAt)
        XCTAssertEqual(op.remoteVersion, 0)
        XCTAssertEqual(op.localVersion, 1)
        XCTAssertEqual(op.operationType, .create)
        XCTAssertEqual(op.entityType, .customer)
    }

    func testPendingUpdateAndDelete() throws {
        let update = try SyncOperation.pending(
            entityType: .user,
            entityId: "u-1",
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            remoteVersion: 1
        )
        let delete = try SyncOperation.pending(
            entityType: .workOrderNote,
            entityId: "n-1",
            operationType: .delete,
            payloadReference: "wo-1",
            createdAt: now,
            localVersion: 3
        )
        XCTAssertEqual(update.operationType, .update)
        XCTAssertEqual(delete.operationType, .delete)
        XCTAssertEqual(update.status, .pending)
        XCTAssertEqual(delete.status, .pending)
    }

    func testIdempotencyKeyIsDeterministicAndUniquePerVersion() throws {
        let a = try SyncOperation.pending(
            entityType: .workOrder,
            entityId: "wo-1",
            operationType: .update,
            createdAt: now,
            localVersion: 4
        )
        let b = try SyncOperation.pending(
            id: SyncOperationID("other"),
            entityType: .workOrder,
            entityId: "wo-1",
            operationType: .update,
            createdAt: now,
            localVersion: 4
        )
        let later = try SyncOperation.pending(
            entityType: .workOrder,
            entityId: "wo-1",
            operationType: .update,
            createdAt: now,
            localVersion: 5
        )
        XCTAssertEqual(a.idempotencyKey, b.idempotencyKey)
        XCTAssertEqual(a.idempotencyKey.rawValue, "workOrder:wo-1:update:v4")
        XCTAssertNotEqual(a.idempotencyKey, later.idempotencyKey)
    }

    func testEmptyEntityIdIsRejected() {
        XCTAssertThrowsError(
            try SyncOperation.pending(
                entityType: .customer,
                entityId: "  ",
                operationType: .create,
                createdAt: now,
                localVersion: 1
            )
        ) { error in
            XCTAssertEqual(error as? SyncError, .invalidPayload)
        }
    }

    func testForbiddenCombinationIsRejected() {
        XCTAssertThrowsError(
            try SyncOperation.pending(
                entityType: .notification,
                entityId: "n-1",
                operationType: .delete,
                createdAt: now,
                localVersion: 1
            )
        ) { error in
            XCTAssertEqual(error as? SyncError, .invalidPayload)
        }
    }

    func testCompletedWorkOrderUpdateCannotBeEnqueued() {
        XCTAssertThrowsError(
            try SyncOperation.pending(
                entityType: .workOrder,
                entityId: "wo-1",
                operationType: .update,
                createdAt: now,
                localVersion: 2,
                workOrderStatus: .completed
            )
        ) { error in
            XCTAssertEqual(error as? SyncError, .invalidPayload)
        }
    }

    func testCompletionTransitionUpdateCanBeEnqueuedWithDependency() throws {
        let dependencyId = SyncOperationID("gps-create-op")
        let op = try SyncOperation.pending(
            entityType: .workOrder,
            entityId: "wo-1",
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            workOrderStatus: .completed,
            dependsOnOperationId: dependencyId,
            allowsCompletedWorkOrderUpdate: true
        )
        XCTAssertEqual(op.dependsOnOperationId, dependencyId)
        XCTAssertEqual(op.status, .pending)
    }

    func testWorkOrderChildRequiresPayloadReference() {
        XCTAssertThrowsError(
            try SyncOperation.pending(
                entityType: .workOrderNote,
                entityId: "n-1",
                operationType: .create,
                createdAt: now,
                localVersion: 1
            )
        ) { error in
            XCTAssertEqual(error as? SyncError, .invalidPayload)
        }
        XCTAssertThrowsError(
            try SyncOperation.pending(
                entityType: .signature,
                entityId: "s-1",
                operationType: .create,
                payloadReference: "   ",
                createdAt: now,
                localVersion: 1
            )
        ) { error in
            XCTAssertEqual(error as? SyncError, .invalidPayload)
        }
    }

    func testWorkOrderChildAcceptsParentPayloadReference() throws {
        let op = try SyncOperation.pending(
            entityType: .workOrderPhoto,
            entityId: "p-1",
            operationType: .create,
            payloadReference: "wo-42",
            createdAt: now,
            localVersion: 1
        )
        XCTAssertEqual(op.payloadReference, "wo-42")
    }
}
