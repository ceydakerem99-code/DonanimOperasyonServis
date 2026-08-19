import XCTest
@testable import DonanimOperasyonServis

final class ReconciliationPolicyTests: XCTestCase {

    func testSameContentsIsNoChange() {
        XCTAssertEqual(ReconciliationPolicy.decide(facts(equal: true)), .noChange)
        XCTAssertEqual(ReconciliationResult.noChange.displayName, "Değişiklik Yok")
        XCTAssertEqual(ReconciliationResult.applyRemote.displayName, "Sunucu Verisini Kullan")
        XCTAssertEqual(ReconciliationResult.keepLocal.displayName, "Yerel Veriyi Koru")
        XCTAssertEqual(ReconciliationResult.conflict.displayName, "Çakışma")
    }

    func testRemoteNewerWithoutPendingIsApplyRemote() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: 1,
                remoteVersion: 2,
                lastSynced: 1,
                pending: false
            )),
            .applyRemote
        )
    }

    func testPendingUpdateWithUnchangedRemoteIsKeepLocal() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: 2,
                remoteVersion: 1,
                lastSynced: 1,
                pending: true
            )),
            .keepLocal
        )
    }

    func testPendingUpdateWithNewerRemoteIsConflict() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: 2,
                remoteVersion: 3,
                lastSynced: 1,
                pending: true
            )),
            .conflict
        )
    }

    func testBothChangedWithoutReliableVersionsIsConflict() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: nil,
                remoteVersion: nil,
                lastSynced: nil,
                pending: false
            )),
            .conflict
        )
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: 1,
                remoteVersion: 2,
                lastSynced: 1,
                pending: false
            )),
            .applyRemote
        )
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: nil,
                remoteVersion: 2,
                lastSynced: 1,
                pending: false
            )),
            .conflict
        )
    }

    func testCompletedVersusInProgressIsConflict() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                entityType: .workOrder,
                localStatus: .completed,
                remoteStatus: .inProgress
            )),
            .conflict
        )
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                entityType: .workOrder,
                localStatus: .inProgress,
                remoteStatus: .completed
            )),
            .conflict
        )
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                entityType: .workOrder,
                localStatus: .completed,
                remoteStatus: .paused
            )),
            .conflict
        )
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                entityType: .workOrder,
                localStatus: .completed,
                remoteStatus: .accepted
            )),
            .conflict
        )
    }

    func testBothCompletedEqualIsNoChange() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: true,
                entityType: .workOrder,
                localStatus: .completed,
                remoteStatus: .completed
            )),
            .noChange
        )
    }

    func testBothCompletedDifferFollowsVersionPolicy() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: 1,
                remoteVersion: 2,
                lastSynced: 1,
                pending: false,
                entityType: .workOrder,
                localStatus: .completed,
                remoteStatus: .completed
            )),
            .applyRemote
        )
    }

    func testRemoteMissingWithPendingKeepsLocal() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                localExists: true,
                remoteExists: false,
                equal: false,
                pending: true
            )),
            .keepLocal
        )
    }

    func testRemoteMissingWithoutPendingIsConflict() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                localExists: true,
                remoteExists: false,
                equal: false,
                pending: false
            )),
            .conflict
        )
    }

    func testLocalMissingRemotePresentWithoutPendingAppliesRemote() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                localExists: false,
                remoteExists: true,
                equal: false,
                localVersion: nil,
                remoteVersion: 3,
                lastSynced: 0,
                pending: false
            )),
            .applyRemote
        )
    }

    func testLocalMissingWithPendingDeleteKeepsLocal() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                localExists: false,
                remoteExists: true,
                equal: false,
                pending: true
            )),
            .keepLocal
        )
    }

    func testRemoteOlderThanLastSyncIsConflict() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: 1,
                remoteVersion: 1,
                lastSynced: 4,
                pending: false
            )),
            .conflict
        )
    }

    func testNoPendingRemoteUnchangedContentsDifferKeepsLocal() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                localVersion: 2,
                remoteVersion: 1,
                lastSynced: 1,
                pending: false
            )),
            .keepLocal
        )
    }

    func testDifferingEditRequestsAreConflictNotAutoApproved() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: false,
                entityType: .editRequest
            )),
            .conflict
        )
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                equal: true,
                entityType: .editRequest
            )),
            .noChange
        )
    }

    func testNeitherSideExistsIsNoChange() {
        XCTAssertEqual(
            ReconciliationPolicy.decide(facts(
                localExists: false,
                remoteExists: false,
                equal: true
            )),
            .noChange
        )
    }

    func testInvalidVersionsNeverAutoPreferRemote() {
        XCTAssertFalse(EntityVersionPolicy.isValid(nil))
        XCTAssertFalse(EntityVersionPolicy.isValid(-1))
        XCTAssertTrue(EntityVersionPolicy.isValid(0))
        XCTAssertEqual(
            EntityVersionPolicy.remoteProgress(current: 2, lastSynced: 1),
            .newer
        )
        XCTAssertEqual(
            EntityVersionPolicy.remoteProgress(current: 1, lastSynced: 1),
            .unchanged
        )
        XCTAssertEqual(
            EntityVersionPolicy.remoteProgress(current: nil, lastSynced: 1),
            .unknown
        )
    }

    // MARK: - Helper

    private func facts(
        localExists: Bool = true,
        remoteExists: Bool = true,
        equal: Bool = false,
        localVersion: Int? = 1,
        remoteVersion: Int? = 1,
        lastSynced: Int? = 1,
        pending: Bool = false,
        entityType: SyncEntityType = .customer,
        localStatus: WorkOrderStatus? = nil,
        remoteStatus: WorkOrderStatus? = nil
    ) -> ReconciliationFacts {
        ReconciliationFacts(
            entityType: entityType,
            entityId: "e-1",
            localExists: localExists,
            remoteExists: remoteExists,
            contentsEqual: equal,
            versions: ReconciliationVersionState(
                localVersion: localVersion,
                remoteVersion: remoteVersion,
                lastSyncedRemoteVersion: lastSynced
            ),
            hasPendingLocalMutation: pending,
            pendingOperationId: pending ? SyncOperationID("op-1") : nil,
            localWorkOrderStatus: localStatus,
            remoteWorkOrderStatus: remoteStatus
        )
    }
}
