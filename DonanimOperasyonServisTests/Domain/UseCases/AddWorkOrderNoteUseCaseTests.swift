import XCTest
@testable import DonanimOperasyonServis

final class AddWorkOrderNoteUseCaseTests: XCTestCase {

    func makeUseCase() -> (
        AddWorkOrderNoteUseCase,
        InMemoryWorkOrderRepository,
        InMemoryNoteRepository
    ) {
        let orders = InMemoryWorkOrderRepository()
        let notes = InMemoryNoteRepository()
        let useCase = AddWorkOrderNoteUseCase(
            workOrderRepository: orders,
            noteRepository: notes
        )
        return (useCase, orders, notes)
    }

    func testAssignedTechnicianCanAddNote() async throws {
        let (useCase, orders, notes) = makeUseCase()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        try await orders.save(order)

        let note = try await useCase.execute(
            actor: tech,
            orderId: order.id,
            text: "  Cihaz temizlendi  ",
            at: DomainFixtures.referenceDate
        )

        XCTAssertEqual(note.workOrderId, order.id)
        XCTAssertEqual(note.authorUserId, tech.id)
        XCTAssertEqual(note.text, "Cihaz temizlendi")
        XCTAssertEqual(note.createdAt, DomainFixtures.referenceDate)
        let stored = try await notes.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
    }

    func testEmptyNoteRejected() async {
        let (useCase, orders, _) = makeUseCase()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(assignedTechnicianId: tech.id, status: .inProgress)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(actor: tech, orderId: order.id, text: "   ")
            XCTFail("expected invalidData")
        } catch let error as DomainError {
            guard case .invalidData(let reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(reason, "note.textEmpty")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testOtherTechnicianUnauthorized() async {
        let (useCase, orders, _) = makeUseCase()
        let assigned = DomainFixtures.technicianUser(id: UserID("tech-a"))
        let other = DomainFixtures.technicianUser(id: UserID("tech-b"), email: "b@example.com")
        let order = DomainFixtures.workOrder(assignedTechnicianId: assigned.id, status: .inProgress)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(actor: other, orderId: order.id, text: "Not")
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCompletedWorkOrderLocked() async {
        let (useCase, orders, _) = makeUseCase()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(assignedTechnicianId: tech.id, status: .completed)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(actor: tech, orderId: order.id, text: "Not")
            XCTFail("expected locked")
        } catch let error as DomainError {
            guard case .workOrderLocked = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testOperatorUnauthorized() async {
        let (useCase, orders, _) = makeUseCase()
        let op = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(assignedTechnicianId: tech.id, status: .inProgress)
        try? await orders.save(order)

        do {
            _ = try await useCase.execute(actor: op, orderId: order.id, text: "Not")
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
