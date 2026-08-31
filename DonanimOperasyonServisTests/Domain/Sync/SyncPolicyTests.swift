import XCTest
@testable import DonanimOperasyonServis

final class SyncPolicyTests: XCTestCase {

    func testCoreEntityOperationMatrix() {
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .workOrder, operationType: .create))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .workOrder, operationType: .update))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .workOrder, operationType: .delete))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .customer, operationType: .create))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .customer, operationType: .update))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .customer, operationType: .delete))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .editRequest, operationType: .create))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .editRequest, operationType: .update))
        XCTAssertFalse(SyncPolicy.canEnqueue(entityType: .editRequest, operationType: .delete))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .notification, operationType: .create))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .notification, operationType: .update))
        XCTAssertFalse(SyncPolicy.canEnqueue(entityType: .notification, operationType: .delete))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .customerSatisfaction, operationType: .create))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .customerSatisfaction, operationType: .update))
        XCTAssertFalse(SyncPolicy.canEnqueue(entityType: .customerSatisfaction, operationType: .delete))
    }

    func testAppendOnlyChildren() {
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .workOrderStatusHistory, operationType: .create))
        XCTAssertFalse(SyncPolicy.canEnqueue(entityType: .workOrderStatusHistory, operationType: .update))
        XCTAssertFalse(SyncPolicy.canEnqueue(entityType: .workOrderStatusHistory, operationType: .delete))
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .workOrderLocation, operationType: .create))
        XCTAssertFalse(SyncPolicy.canEnqueue(entityType: .workOrderLocation, operationType: .delete))
    }

    func testCompletedWorkOrderBlocksUpdateAndDelete() {
        XCTAssertFalse(
            SyncPolicy.canEnqueue(
                entityType: .workOrder,
                operationType: .update,
                workOrderStatus: .completed
            )
        )
        XCTAssertFalse(
            SyncPolicy.canEnqueue(
                entityType: .workOrder,
                operationType: .delete,
                workOrderStatus: .completed
            )
        )
        XCTAssertTrue(
            SyncPolicy.canEnqueue(
                entityType: .workOrder,
                operationType: .update,
                workOrderStatus: .inProgress
            )
        )
    }

    func testCompletionTransitionMayEnqueueCompletedWorkOrderUpdate() {
        XCTAssertTrue(
            SyncPolicy.canEnqueue(
                entityType: .workOrder,
                operationType: .update,
                workOrderStatus: .completed,
                allowsCompletedWorkOrderUpdate: true
            )
        )
        XCTAssertFalse(
            SyncPolicy.canEnqueue(
                entityType: .workOrder,
                operationType: .delete,
                workOrderStatus: .completed,
                allowsCompletedWorkOrderUpdate: true
            )
        )
    }

    func testEditRequestRemainsThePathForCompletedFieldEdits() {
        XCTAssertTrue(SyncPolicy.canEnqueue(entityType: .editRequest, operationType: .create))
        XCTAssertFalse(
            SyncPolicy.canEnqueue(
                entityType: .workOrder,
                operationType: .update,
                workOrderStatus: .completed
            )
        )
    }

    func testWorkOrderChildrenRequirePayloadReference() {
        XCTAssertTrue(SyncPolicy.requiresWorkOrderPayloadReference(.workOrderNote))
        XCTAssertTrue(SyncPolicy.requiresWorkOrderPayloadReference(.workOrderPhoto))
        XCTAssertTrue(SyncPolicy.requiresWorkOrderPayloadReference(.workOrderLocation))
        XCTAssertTrue(SyncPolicy.requiresWorkOrderPayloadReference(.workOrderStatusHistory))
        XCTAssertTrue(SyncPolicy.requiresWorkOrderPayloadReference(.signature))
        XCTAssertFalse(SyncPolicy.requiresWorkOrderPayloadReference(.workOrder))
        XCTAssertFalse(SyncPolicy.requiresWorkOrderPayloadReference(.customer))
        XCTAssertFalse(SyncPolicy.requiresWorkOrderPayloadReference(.notification))
        XCTAssertFalse(SyncPolicy.requiresWorkOrderPayloadReference(.customerSatisfaction))
    }
}
