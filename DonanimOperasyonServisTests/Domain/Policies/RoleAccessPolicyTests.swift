import XCTest
@testable import DonanimOperasyonServis

final class RoleAccessPolicyTests: XCTestCase {

    // MARK: - Admin permissions

    func testAdminAdministrativeActions() {
        XCTAssertTrue(RoleAccessPolicy.can(.manageUsers, as: .admin))
        XCTAssertTrue(RoleAccessPolicy.can(.viewRolesMatrix, as: .admin))
        XCTAssertTrue(RoleAccessPolicy.can(.manageSystemConfiguration, as: .admin))
        XCTAssertTrue(RoleAccessPolicy.can(.viewSystemReports, as: .admin))
    }

    func testAdminCannotApproveOrRejectEditRequests() {
        XCTAssertFalse(RoleAccessPolicy.can(.approveEditRequest, as: .admin))
        XCTAssertFalse(RoleAccessPolicy.can(.rejectEditRequest, as: .admin))
        XCTAssertFalse(RoleAccessPolicy.can(.resolveSyncConflict, as: .admin))
    }

    func testAdminCannotPerformFieldWork() {
        let technicianActions: [DomainAction] = [
            .acceptWorkOrder, .startTravelToCustomer, .markArrivedAtCustomer,
            .startServiceWork, .pauseServiceWork, .resumeServiceWork,
            .addWorkOrderNote, .addWorkOrderPhoto, .captureLocationSample,
            .captureSignature, .completeWorkOrder, .createEditRequest
        ]
        for action in technicianActions {
            XCTAssertFalse(
                RoleAccessPolicy.can(action, as: .admin),
                "Admin must not be able to perform \(action)"
            )
        }
    }

    func testAdminCannotCreateOperationalEntities() {
        XCTAssertFalse(RoleAccessPolicy.can(.createWorkOrder, as: .admin))
        XCTAssertFalse(RoleAccessPolicy.can(.createCustomer, as: .admin))
        XCTAssertFalse(RoleAccessPolicy.can(.assignWorkOrder, as: .admin))
    }

    // MARK: - Operator permissions

    func testOperatorOperationalActions() {
        XCTAssertTrue(RoleAccessPolicy.can(.createWorkOrder, as: .operator))
        XCTAssertTrue(RoleAccessPolicy.can(.createCustomer, as: .operator))
        XCTAssertTrue(RoleAccessPolicy.can(.assignWorkOrder, as: .operator))
        XCTAssertTrue(RoleAccessPolicy.can(.viewAllWorkOrders, as: .operator))
        XCTAssertTrue(RoleAccessPolicy.can(.viewServiceReport, as: .operator))
        XCTAssertTrue(RoleAccessPolicy.can(.approveEditRequest, as: .operator))
        XCTAssertTrue(RoleAccessPolicy.can(.rejectEditRequest, as: .operator))
        XCTAssertTrue(RoleAccessPolicy.can(.resolveSyncConflict, as: .operator))
    }

    func testOperatorCannotAdminister() {
        XCTAssertFalse(RoleAccessPolicy.can(.manageUsers, as: .operator))
        XCTAssertFalse(RoleAccessPolicy.can(.viewRolesMatrix, as: .operator))
        XCTAssertFalse(RoleAccessPolicy.can(.manageSystemConfiguration, as: .operator))
    }

    // MARK: - Technician permissions

    func testTechnicianFieldWorkActions() {
        let technicianActions: [DomainAction] = [
            .viewOwnAssignedWorkOrders,
            .acceptWorkOrder, .startTravelToCustomer, .markArrivedAtCustomer,
            .startServiceWork, .pauseServiceWork, .resumeServiceWork,
            .addWorkOrderNote, .addWorkOrderPhoto, .captureLocationSample,
            .captureSignature, .completeWorkOrder, .createEditRequest
        ]
        for action in technicianActions {
            XCTAssertTrue(
                RoleAccessPolicy.can(action, as: .technician),
                "Technician must be able to perform \(action)"
            )
        }
    }

    func testTechnicianCannotOperateOrAdminister() {
        XCTAssertFalse(RoleAccessPolicy.can(.createWorkOrder, as: .technician))
        XCTAssertFalse(RoleAccessPolicy.can(.assignWorkOrder, as: .technician))
        XCTAssertFalse(RoleAccessPolicy.can(.approveEditRequest, as: .technician))
        XCTAssertFalse(RoleAccessPolicy.can(.rejectEditRequest, as: .technician))
        XCTAssertFalse(RoleAccessPolicy.can(.resolveSyncConflict, as: .technician))
        XCTAssertFalse(RoleAccessPolicy.can(.manageUsers, as: .technician))
    }

    // MARK: - Contextual: canAct

    func testTechnicianCanActOnlyOnOwnAssignedOrder() {
        let alice = DomainFixtures.technicianUser(id: UserID("tech-alice"))
        let bob = DomainFixtures.technicianUser(id: UserID("tech-bob"))
        let order = DomainFixtures.workOrder(assignedTechnicianId: alice.id, status: .accepted)

        XCTAssertTrue(RoleAccessPolicy.canAct(on: order, as: alice))
        XCTAssertFalse(RoleAccessPolicy.canAct(on: order, as: bob))
    }

    func testTechnicianCannotActOnCompletedOrder() {
        let tech = DomainFixtures.technicianUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        XCTAssertFalse(RoleAccessPolicy.canAct(on: completed, as: tech))
    }

    func testOperatorAndAdminCannotActOnWorkOrder() {
        let op = DomainFixtures.operatorUser()
        let admin = DomainFixtures.adminUser()
        let order = DomainFixtures.workOrder(status: .accepted)
        XCTAssertFalse(RoleAccessPolicy.canAct(on: order, as: op))
        XCTAssertFalse(RoleAccessPolicy.canAct(on: order, as: admin))
    }

    // MARK: - Contextual: canRequestEdit

    func testTechnicianCanRequestEditOnOwnCompletedOrder() {
        let tech = DomainFixtures.technicianUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        XCTAssertTrue(RoleAccessPolicy.canRequestEdit(on: completed, as: tech))
    }

    func testTechnicianCannotRequestEditWhenNotCompleted() {
        let tech = DomainFixtures.technicianUser()
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        XCTAssertFalse(RoleAccessPolicy.canRequestEdit(on: inProgress, as: tech))
    }

    func testTechnicianCannotRequestEditOnAnotherTechniciansOrder() {
        let alice = DomainFixtures.technicianUser(id: UserID("tech-alice"))
        let bob = DomainFixtures.technicianUser(id: UserID("tech-bob"))
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: alice.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        XCTAssertFalse(RoleAccessPolicy.canRequestEdit(on: completed, as: bob))
    }

    // MARK: - Contextual: canReviewEditRequest

    func testOnlyOperatorCanReviewEditRequest() {
        let admin = DomainFixtures.adminUser()
        let op = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser()
        let request = DomainFixtures.editRequest(requestedByUserId: tech.id)

        XCTAssertFalse(RoleAccessPolicy.canReviewEditRequest(request, as: admin))
        XCTAssertTrue(RoleAccessPolicy.canReviewEditRequest(request, as: op))
        XCTAssertFalse(RoleAccessPolicy.canReviewEditRequest(request, as: tech))
    }

    func testOperatorCannotReviewTheirOwnRequest() {
        let op = DomainFixtures.operatorUser()
        let request = DomainFixtures.editRequest(requestedByUserId: op.id)
        XCTAssertFalse(RoleAccessPolicy.canReviewEditRequest(request, as: op))
    }
}
