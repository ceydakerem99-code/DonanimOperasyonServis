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
        XCTAssertEqual(Set(SyncConflictResolutionChoice.allCases), [.useLocal, .useRemote])
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
