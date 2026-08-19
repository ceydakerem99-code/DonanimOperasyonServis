import XCTest
@testable import DonanimOperasyonServis

final class ConflictResolutionPolicyTests: XCTestCase {

    func testUnresolvedIsAlwaysAllowed() {
        let completed = ConflictResolutionFacts(
            entityType: .workOrder,
            localWorkOrderStatus: .completed,
            remoteWorkOrderStatus: .inProgress
        )
        let edit = ConflictResolutionFacts(
            entityType: .editRequest,
            localWorkOrderStatus: nil,
            remoteWorkOrderStatus: nil
        )
        XCTAssertTrue(ConflictResolutionPolicy.allows(.unresolved, facts: completed))
        XCTAssertTrue(ConflictResolutionPolicy.allows(.unresolved, facts: edit))
    }

    func testCompletedWorkOrderBlocksUseLocalAndUseRemote() {
        let localCompleted = ConflictResolutionFacts(
            entityType: .workOrder,
            localWorkOrderStatus: .completed,
            remoteWorkOrderStatus: .inProgress
        )
        let remoteCompleted = ConflictResolutionFacts(
            entityType: .workOrder,
            localWorkOrderStatus: .inProgress,
            remoteWorkOrderStatus: .completed
        )
        XCTAssertEqual(
            ConflictResolutionPolicy.restriction(for: localCompleted),
            .completedWorkOrder
        )
        XCTAssertEqual(
            ConflictResolutionPolicy.restriction(for: remoteCompleted),
            .completedWorkOrder
        )
        XCTAssertFalse(ConflictResolutionPolicy.allows(.useLocal, facts: localCompleted))
        XCTAssertFalse(ConflictResolutionPolicy.allows(.useRemote, facts: remoteCompleted))
        XCTAssertEqual(
            ConflictResolutionPolicy.rejectionReason(for: localCompleted),
            "conflict.completedWorkOrderMustStayUnresolved"
        )
    }

    func testBothCompletedStillBlocksResolverMutation() {
        let facts = ConflictResolutionFacts(
            entityType: .workOrder,
            localWorkOrderStatus: .completed,
            remoteWorkOrderStatus: .completed
        )
        XCTAssertEqual(
            ConflictResolutionPolicy.restriction(for: facts),
            .completedWorkOrder
        )
        XCTAssertFalse(ConflictResolutionPolicy.allows(.useRemote, facts: facts))
    }

    func testInProgressVersusAssignedCanBeResolved() {
        let facts = ConflictResolutionFacts(
            entityType: .workOrder,
            localWorkOrderStatus: .inProgress,
            remoteWorkOrderStatus: .assigned
        )
        XCTAssertEqual(ConflictResolutionPolicy.restriction(for: facts), .none)
        XCTAssertTrue(ConflictResolutionPolicy.allows(.useLocal, facts: facts))
        XCTAssertTrue(ConflictResolutionPolicy.allows(.useRemote, facts: facts))
    }

    func testEditRequestMustStayOnWorkflow() {
        let facts = ConflictResolutionFacts(
            entityType: .editRequest,
            localWorkOrderStatus: nil,
            remoteWorkOrderStatus: nil
        )
        XCTAssertEqual(
            ConflictResolutionPolicy.restriction(for: facts),
            .editRequestWorkflow
        )
        XCTAssertFalse(ConflictResolutionPolicy.allows(.useLocal, facts: facts))
        XCTAssertFalse(ConflictResolutionPolicy.allows(.useRemote, facts: facts))
        XCTAssertEqual(
            ConflictResolutionPolicy.rejectionReason(for: facts),
            "conflict.editRequestWorkflowRequired"
        )
    }

    func testCustomerConflictsAreResolvable() {
        let facts = ConflictResolutionFacts(
            entityType: .customer,
            localWorkOrderStatus: nil,
            remoteWorkOrderStatus: nil
        )
        XCTAssertTrue(ConflictResolutionPolicy.allows(.useLocal, facts: facts))
        XCTAssertTrue(ConflictResolutionPolicy.allows(.useRemote, facts: facts))
    }
}
