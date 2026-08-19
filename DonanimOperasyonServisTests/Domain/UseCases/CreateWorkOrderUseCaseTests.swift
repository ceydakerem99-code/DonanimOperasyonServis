import XCTest
@testable import DonanimOperasyonServis

final class CreateWorkOrderUseCaseTests: XCTestCase {

    func makeUseCase() -> (
        useCase: CreateWorkOrderUseCase,
        orders: InMemoryWorkOrderRepository,
        history: InMemoryStatusHistoryRepository
    ) {
        let orders = InMemoryWorkOrderRepository()
        let history = InMemoryStatusHistoryRepository()
        let useCase = CreateWorkOrderUseCase(
            workOrderRepository: orders,
            statusHistoryRepository: history
        )
        return (useCase, orders, history)
    }

    func testOperatorCanCreateWorkOrderAndInitialHistoryEntryIsAppended() async throws {
        let (useCase, orders, history) = makeUseCase()
        let op = DomainFixtures.operatorUser()
        let request = DomainFixtures.newWorkOrderRequest()

        let created = try await useCase.execute(
            actor: op,
            request: request,
            at: DomainFixtures.referenceDate
        )

        XCTAssertEqual(created.status, .assigned)
        XCTAssertEqual(created.createdByUserId, op.id)
        XCTAssertEqual(created.createdAt, DomainFixtures.referenceDate)
        XCTAssertEqual(created.updatedAt, DomainFixtures.referenceDate)
        XCTAssertNil(created.completedAt)

        let stored = try await orders.fetch(id: request.id)
        XCTAssertEqual(stored, created)

        let historyEntries = await history.all()
        XCTAssertEqual(historyEntries.count, 1)
        XCTAssertEqual(historyEntries.first?.fromStatus, nil)
        XCTAssertEqual(historyEntries.first?.toStatus, .assigned)
        XCTAssertEqual(historyEntries.first?.actorUserId, op.id)
    }

    func testTechnicianCannotCreateWorkOrder() async {
        let (useCase, _, _) = makeUseCase()
        let tech = DomainFixtures.technicianUser()

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(actor: tech, request: DomainFixtures.newWorkOrderRequest())
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .createWorkOrder))
        }
    }

    func testAdminCannotCreateWorkOrder() async {
        let (useCase, _, _) = makeUseCase()
        let admin = DomainFixtures.adminUser()

        await XCTAssertThrowsErrorAsync(
            try await useCase.execute(actor: admin, request: DomainFixtures.newWorkOrderRequest())
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .createWorkOrder))
        }
    }

    func testEmptyRequiredFieldRejected() async {
        let (useCase, _, _) = makeUseCase()
        let op = DomainFixtures.operatorUser()
        let request = NewWorkOrderRequest(
            id: WorkOrderID("wo-x"),
            workOrderNumber: "WO-x",
            assignedTechnicianId: UserID("t1"),
            customerId: CustomerID("c1"),
            workType: .installation,
            deviceCategory: .pos,
            deviceBrand: "   ",
            deviceModel: "Model",
            serialNumber: "SN",
            issueDescription: nil,
            priority: .normal,
            scheduledDate: DomainFixtures.referenceDate,
            scheduledTimeRange: nil
        )

        await XCTAssertThrowsErrorAsync(try await useCase.execute(actor: op, request: request)) { error in
            XCTAssertEqual(error as? DomainError, .invalidData(reason: "workOrder.requiredFieldEmpty"))
        }
    }
}
