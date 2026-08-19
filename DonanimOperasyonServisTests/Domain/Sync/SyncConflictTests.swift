import XCTest
@testable import DonanimOperasyonServis

final class SyncConflictTests: XCTestCase {

    func testUnresolvedConflictCapturesVersionsAndReferences() {
        let conflict = SyncConflict.unresolved(
            syncOperationId: SyncOperationID("op-1"),
            entityType: .workOrder,
            entityId: "wo-1",
            localVersion: 4,
            remoteVersion: 3,
            localReference: "local/wo-1",
            remoteReference: "remote/wo-1",
            detectedAt: DomainFixtures.referenceDate
        )
        XCTAssertEqual(conflict.status, .unresolved)
        XCTAssertEqual(conflict.localVersion, 4)
        XCTAssertEqual(conflict.remoteVersion, 3)
        XCTAssertEqual(conflict.localReference, "local/wo-1")
        XCTAssertEqual(conflict.remoteReference, "remote/wo-1")
        XCTAssertNil(conflict.resolution)
        XCTAssertFalse(conflict.isResolved)
        XCTAssertEqual(Set(SyncConflictResolutionChoice.allCases), [.useLocal, .useRemote])
        XCTAssertEqual(Set(SyncConflictStatus.allCases), [.unresolved])
        XCTAssertEqual(
            Set(ConflictResolutionDecision.allCases),
            [.useLocal, .useRemote, .unresolved]
        )
    }

    func testMarkingResolvedPreservesDetectionSnapshot() {
        let original = SyncConflict.unresolved(
            id: SyncConflictID("cf-snap"),
            syncOperationId: SyncOperationID("op-1"),
            entityType: .customer,
            entityId: "cust-1",
            localVersion: 4,
            remoteVersion: 7,
            localReference: "local/cust-1/v4",
            remoteReference: "remote/cust-1/v7",
            detectedAt: DomainFixtures.referenceDate
        )
        let resolved = original.markingResolved(
            choice: .useLocal,
            at: DomainFixtures.referenceDate.addingTimeInterval(30),
            by: UserID("user-operator-1")
        )
        XCTAssertEqual(resolved.localVersion, 4)
        XCTAssertEqual(resolved.remoteVersion, 7)
        XCTAssertEqual(resolved.localReference, "local/cust-1/v4")
        XCTAssertEqual(resolved.remoteReference, "remote/cust-1/v7")
        XCTAssertEqual(resolved.detectedAt, original.detectedAt)
        XCTAssertEqual(resolved.resolution, .useLocal)
        XCTAssertTrue(resolved.isResolved)
        XCTAssertEqual(resolved.status, .unresolved)
    }

    func testCompletedVersusInProgressIsConflict() {
        XCTAssertEqual(
            CompletedWorkOrderSyncRule.classify(local: .completed, remote: .inProgress),
            .conflict
        )
        XCTAssertEqual(
            CompletedWorkOrderSyncRule.classify(local: .inProgress, remote: .completed),
            .conflict
        )
        XCTAssertTrue(CompletedWorkOrderSyncRule.isConflict(local: .completed, remote: .assigned))
        XCTAssertTrue(CompletedWorkOrderSyncRule.isConflict(local: .paused, remote: .completed))
    }

    func testMatchingStatusesAreNotConflicts() {
        for status in WorkOrderStatus.allCases {
            XCTAssertEqual(
                CompletedWorkOrderSyncRule.classify(local: status, remote: status),
                .none
            )
        }
    }

    func testNonCompletedDivergenceIsOtherNotAutoResolved() {
        XCTAssertEqual(
            CompletedWorkOrderSyncRule.classify(local: .inProgress, remote: .assigned),
            .other
        )
    }

    func testRuleNeverRewritesCompletedToInProgress() {
        // The rule only classifies; it does not return a status to
        // write. A conflict must stay a conflict.
        let outcome = CompletedWorkOrderSyncRule.classify(local: .inProgress, remote: .completed)
        XCTAssertNotEqual(outcome, .none)
        XCTAssertEqual(outcome, .conflict)
    }
}
