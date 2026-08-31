import XCTest
@testable import DonanimOperasyonServis

final class AssignWorkOrderUseCaseTests: XCTestCase {

    func makeUseCase() -> (AssignWorkOrderUseCase, InMemoryWorkOrderRepository) {
        let orders = InMemoryWorkOrderRepository()
        return (AssignWorkOrderUseCase(workOrderRepository: orders), orders)
    }

    func testOperatorCanReassignTechnician() async throws {
        let (useCase, orders) = makeUseCase()
        let op = DomainFixtures.operatorUser()
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"))
        let techB = DomainFixtures.technicianUser(id: UserID("tech-b"))
        let order = DomainFixtures.workOrder(assignedTechnicianId: techA.id, status: .assigned)
        try await orders.save(order)

        let updated = try await useCase.execute(
            actor: op,
            orderId: order.id,
            newTechnicianId: techB.id,
            at: DomainFixtures.referenceDate
        )

        XCTAssertEqual(updated.assignedTechnicianId, techB.id)
        XCTAssertEqual(updated.updatedAt, DomainFixtures.referenceDate)
        let stored = try await orders.fetch(id: order.id)
        XCTAssertEqual(stored.assignedTechnicianId, techB.id)
    }

    func testTechnicianUnauthorized() async {
        let (useCase, orders) = makeUseCase()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(assignedTechnicianId: tech.id)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(
                actor: tech,
                orderId: order.id,
                newTechnicianId: UserID("other")
            )
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized(let action) = error else {
                return XCTFail("expected unauthorized, got \(error)")
            }
            XCTAssertEqual(action, .assignWorkOrder)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCompletedWorkOrderCannotBeReassigned() async {
        let (useCase, orders) = makeUseCase()
        let op = DomainFixtures.operatorUser()
        let order = DomainFixtures.workOrder(status: .completed)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(
                actor: op,
                orderId: order.id,
                newTechnicianId: UserID("tech-x")
            )
            XCTFail("expected locked")
        } catch let error as DomainError {
            guard case .workOrderLocked = error else {
                return XCTFail("expected locked, got \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
