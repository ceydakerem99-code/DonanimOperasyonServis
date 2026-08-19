import XCTest
@testable import DonanimOperasyonServis

final class EditRequestUseCasesTests: XCTestCase {

    // MARK: - CreateEditRequest

    func testTechnicianCanCreateEditRequestOnOwnCompletedOrder() async throws {
        let tech = DomainFixtures.technicianUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        let orders = InMemoryWorkOrderRepository(seed: [completed])
        let edits = InMemoryEditRequestRepository()
        let useCase = CreateEditRequestUseCase(
            workOrderRepository: orders,
            editRequestRepository: edits
        )

        let created = try await useCase.execute(
            actor: tech,
            orderId: completed.id,
            requestId: EditRequestID("edit-1"),
            field: .issueDescription,
            currentValue: "Eski",
            requestedValue: "Yeni",
            reason: "Yanlış girildi"
        )

        XCTAssertEqual(created.status, .pending)
        XCTAssertEqual(created.requestedByUserId, tech.id)
        XCTAssertEqual(created.field, EditableWorkOrderField.issueDescription.rawValue)
    }

    func testCannotCreateEditRequestOnNonCompletedOrder() async {
        let tech = DomainFixtures.technicianUser()
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let useCase = CreateEditRequestUseCase(
            workOrderRepository: InMemoryWorkOrderRepository(seed: [inProgress]),
            editRequestRepository: InMemoryEditRequestRepository()
        )

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(
                actor: tech,
                orderId: inProgress.id,
                requestId: EditRequestID("e"),
                field: .issueDescription,
                currentValue: "a",
                requestedValue: "b",
                reason: "r"
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidEditRequest(reason: .workOrderNotCompleted)
            )
        }
    }

    func testCannotCreateEditRequestWithNoChange() async {
        let tech = DomainFixtures.technicianUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        let useCase = CreateEditRequestUseCase(
            workOrderRepository: InMemoryWorkOrderRepository(seed: [completed]),
            editRequestRepository: InMemoryEditRequestRepository()
        )

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(
                actor: tech,
                orderId: completed.id,
                requestId: EditRequestID("e"),
                field: .issueDescription,
                currentValue: "same",
                requestedValue: "same",
                reason: "r"
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidEditRequest(reason: .noChange))
        }
    }

    // MARK: - Approve

    func testOperatorCanApproveAndFieldIsAppliedToWorkOrder() async throws {
        let tech = DomainFixtures.technicianUser()
        let op = DomainFixtures.operatorUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            issueDescription: "Eski açıklama",
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        let request = DomainFixtures.editRequest(
            workOrderId: completed.id,
            requestedByUserId: tech.id,
            field: .issueDescription,
            currentValue: "Eski açıklama",
            requestedValue: "Yeni açıklama"
        )
        let orders = InMemoryWorkOrderRepository(seed: [completed])
        let edits = InMemoryEditRequestRepository(seed: [request])
        let useCase = ApproveEditRequestUseCase(
            editRequestRepository: edits,
            workOrderRepository: orders
        )
        let now = DomainFixtures.referenceDate.addingTimeInterval(120)

        let decided = try await useCase.execute(actor: op, requestId: request.id, at: now)

        XCTAssertEqual(decided.status, .approved)
        XCTAssertEqual(decided.reviewedByUserId, op.id)
        XCTAssertEqual(decided.reviewedAt, now)

        let updatedOrder = try await orders.fetch(id: completed.id)
        XCTAssertEqual(updatedOrder.issueDescription, "Yeni açıklama")
        XCTAssertEqual(updatedOrder.status, .completed, "approving a request must NOT re-open the order")
        XCTAssertEqual(updatedOrder.updatedAt, now)
    }

    func testAdminCannotApproveEditRequest() async {
        let admin = DomainFixtures.adminUser()
        let request = DomainFixtures.editRequest()
        let orders = InMemoryWorkOrderRepository(
            seed: [DomainFixtures.workOrder(status: .completed, completedAt: DomainFixtures.referenceDate)]
        )
        let edits = InMemoryEditRequestRepository(seed: [request])
        let useCase = ApproveEditRequestUseCase(
            editRequestRepository: edits,
            workOrderRepository: orders
        )

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(actor: admin, requestId: request.id)
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .approveEditRequest))
        }
    }

    func testTechnicianCannotApproveOwnRequest() async {
        let tech = DomainFixtures.technicianUser()
        let request = DomainFixtures.editRequest(requestedByUserId: tech.id)
        let orders = InMemoryWorkOrderRepository(
            seed: [DomainFixtures.workOrder(status: .completed, completedAt: DomainFixtures.referenceDate)]
        )
        let edits = InMemoryEditRequestRepository(seed: [request])
        let useCase = ApproveEditRequestUseCase(
            editRequestRepository: edits,
            workOrderRepository: orders
        )

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(actor: tech, requestId: request.id)
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .approveEditRequest))
        }
    }

    func testCannotApproveTwice() async throws {
        let op = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            issueDescription: "Eski",
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        let alreadyApproved = DomainFixtures.editRequest(
            workOrderId: completed.id,
            requestedByUserId: tech.id,
            status: .approved,
            reviewedByUserId: op.id,
            reviewedAt: DomainFixtures.referenceDate
        )
        let orders = InMemoryWorkOrderRepository(seed: [completed])
        let edits = InMemoryEditRequestRepository(seed: [alreadyApproved])
        let useCase = ApproveEditRequestUseCase(
            editRequestRepository: edits,
            workOrderRepository: orders
        )

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(actor: op, requestId: alreadyApproved.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidEditRequestTransition(from: .approved, to: .approved)
            )
        }
    }

    // MARK: - Reject

    func testOperatorCanRejectAndOrderStaysUntouched() async throws {
        let tech = DomainFixtures.technicianUser()
        let op = DomainFixtures.operatorUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            issueDescription: "Orijinal",
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        let request = DomainFixtures.editRequest(
            workOrderId: completed.id,
            requestedByUserId: tech.id,
            field: .issueDescription,
            currentValue: "Orijinal",
            requestedValue: "Yeni değer"
        )
        let orders = InMemoryWorkOrderRepository(seed: [completed])
        let edits = InMemoryEditRequestRepository(seed: [request])
        let useCase = RejectEditRequestUseCase(editRequestRepository: edits)

        let now = DomainFixtures.referenceDate.addingTimeInterval(240)
        let decided = try await useCase.execute(
            actor: op,
            requestId: request.id,
            decisionNote: "Uygun değil",
            at: now
        )

        XCTAssertEqual(decided.status, .rejected)
        XCTAssertEqual(decided.reviewedByUserId, op.id)
        XCTAssertEqual(decided.reviewedAt, now)
        XCTAssertEqual(decided.decisionNote, "Uygun değil")

        // Work order must be untouched
        let workOrder = try await orders.fetch(id: completed.id)
        XCTAssertEqual(workOrder.issueDescription, "Orijinal")
        XCTAssertEqual(workOrder.updatedAt, DomainFixtures.referenceDate)
    }

    func testAdminCannotRejectEditRequest() async {
        let admin = DomainFixtures.adminUser()
        let request = DomainFixtures.editRequest()
        let edits = InMemoryEditRequestRepository(seed: [request])
        let useCase = RejectEditRequestUseCase(editRequestRepository: edits)

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(actor: admin, requestId: request.id)
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .rejectEditRequest))
        }
    }

    func testCannotRejectAfterApproval() async {
        let op = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser()
        let approved = DomainFixtures.editRequest(
            requestedByUserId: tech.id,
            status: .approved,
            reviewedByUserId: op.id,
            reviewedAt: DomainFixtures.referenceDate
        )
        let edits = InMemoryEditRequestRepository(seed: [approved])
        let useCase = RejectEditRequestUseCase(editRequestRepository: edits)

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(actor: op, requestId: approved.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidEditRequestTransition(from: .approved, to: .rejected)
            )
        }
    }
}
