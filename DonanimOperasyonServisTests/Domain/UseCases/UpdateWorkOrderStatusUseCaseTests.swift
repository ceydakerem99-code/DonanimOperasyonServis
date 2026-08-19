import XCTest
@testable import DonanimOperasyonServis

final class UpdateWorkOrderStatusUseCaseTests: XCTestCase {

    struct Harness {
        let useCase: UpdateWorkOrderStatusUseCase
        let orders: InMemoryWorkOrderRepository
        let history: InMemoryStatusHistoryRepository
    }

    func makeHarness(seed: [WorkOrder] = []) -> Harness {
        let orders = InMemoryWorkOrderRepository(seed: seed)
        let history = InMemoryStatusHistoryRepository()
        return Harness(
            useCase: UpdateWorkOrderStatusUseCase(
                workOrderRepository: orders,
                statusHistoryRepository: history
            ),
            orders: orders,
            history: history
        )
    }

    // MARK: - Happy path

    func testTechnicianCanAcceptAssignedOrder() async throws {
        let tech = DomainFixtures.technicianUser()
        let assigned = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .assigned
        )
        let h = makeHarness(seed: [assigned])
        let now = DomainFixtures.referenceDate.addingTimeInterval(60)

        let updated = try await h.useCase.execute(
            actor: tech,
            orderId: assigned.id,
            newStatus: .accepted,
            at: now
        )

        XCTAssertEqual(updated.status, .accepted)
        XCTAssertEqual(updated.updatedAt, now)
        let entries = await h.history.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.fromStatus, .assigned)
        XCTAssertEqual(entries.first?.toStatus, .accepted)
    }

    func testTechnicianCanPauseAndResume() async throws {
        let tech = DomainFixtures.technicianUser()
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let h = makeHarness(seed: [inProgress])

        let paused = try await h.useCase.execute(
            actor: tech,
            orderId: inProgress.id,
            newStatus: .paused,
            pauseReason: .partWaiting
        )
        XCTAssertEqual(paused.status, .paused)
        XCTAssertEqual(paused.currentPauseReason, .partWaiting)

        let resumed = try await h.useCase.execute(
            actor: tech,
            orderId: inProgress.id,
            newStatus: .inProgress
        )
        XCTAssertEqual(resumed.status, .inProgress)
        XCTAssertNil(resumed.currentPauseReason, "resume must clear the pause reason")
    }

    // MARK: - Authorization

    func testOperatorCannotUpdateStatus() async {
        let op = DomainFixtures.operatorUser()
        let assigned = DomainFixtures.workOrder(status: .assigned)
        let h = makeHarness(seed: [assigned])

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: op, orderId: assigned.id, newStatus: .accepted)
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .acceptWorkOrder))
        }
    }

    func testTechnicianCannotUpdateAnotherTechniciansOrder() async {
        let alice = DomainFixtures.technicianUser(id: UserID("tech-alice"))
        let bob = DomainFixtures.technicianUser(id: UserID("tech-bob"))
        let assigned = DomainFixtures.workOrder(
            assignedTechnicianId: alice.id,
            status: .assigned
        )
        let h = makeHarness(seed: [assigned])

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: bob, orderId: assigned.id, newStatus: .accepted)
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .acceptWorkOrder))
        }
    }

    // MARK: - Completed lock

    func testUpdatingACompletedOrderIsBlocked() async {
        let tech = DomainFixtures.technicianUser()
        let completed = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        let h = makeHarness(seed: [completed])

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: tech, orderId: completed.id, newStatus: .accepted)
        ) { error in
            XCTAssertEqual(error as? DomainError, .workOrderLocked(completed.id))
        }
    }

    // MARK: - Invariants

    func testInvalidTransitionSurfaces() async {
        let tech = DomainFixtures.technicianUser()
        let assigned = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .assigned
        )
        let h = makeHarness(seed: [assigned])

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: tech, orderId: assigned.id, newStatus: .arrived)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidStateTransition(from: .assigned, to: .arrived)
            )
        }
    }

    func testPauseWithoutReasonRejected() async {
        let tech = DomainFixtures.technicianUser()
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let h = makeHarness(seed: [inProgress])

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: tech, orderId: inProgress.id, newStatus: .paused)
        ) { error in
            XCTAssertEqual(error as? DomainError, .invalidData(reason: "workOrder.pauseReasonRequired"))
        }
    }

    func testCompletionMustGoThroughDedicatedUseCase() async {
        let tech = DomainFixtures.technicianUser()
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let h = makeHarness(seed: [inProgress])

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: tech, orderId: inProgress.id, newStatus: .completed)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "workOrder.useCompleteWorkOrderUseCase")
            )
        }
    }
}
