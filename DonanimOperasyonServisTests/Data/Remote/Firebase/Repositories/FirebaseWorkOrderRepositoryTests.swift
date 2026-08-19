import XCTest
@testable import DonanimOperasyonServis

final class FirebaseWorkOrderRepositoryTests: XCTestCase {

    func testSaveThenFetchRoundTrips() async throws {
        let harness = FirebaseTestHarness()
        let order = DomainFixtures.workOrder(
            issueDescription: "POS kablosu",
            priority: .urgent,
            status: .assigned
        )
        try await harness.workOrders.save(order)
        let fetched = try await harness.workOrders.fetch(id: order.id)
        XCTAssertEqual(fetched, order)
    }

    func testFetchUnknownThrowsNotFound() async throws {
        let harness = FirebaseTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.workOrders.fetch(id: WorkOrderID("nope"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "WorkOrder", id: "nope"))
        }
    }

    func testFilterByAssignedTechnician() async throws {
        let harness = FirebaseTestHarness()
        let tech1 = UserID("tech-1")
        let tech2 = UserID("tech-2")
        let a = DomainFixtures.workOrder(id: WorkOrderID("a"), assignedTechnicianId: tech1)
        let b = DomainFixtures.workOrder(id: WorkOrderID("b"), assignedTechnicianId: tech2)
        let c = DomainFixtures.workOrder(id: WorkOrderID("c"), assignedTechnicianId: tech1)
        for order in [a, b, c] { try await harness.workOrders.save(order) }

        let scoped = try await harness.workOrders.list(
            filter: WorkOrderFilter(assignedTechnicianId: tech1)
        )
        XCTAssertEqual(Set(scoped.map(\.id)), Set([a.id, c.id]))
    }

    func testFilterByStatusPriorityWorkTypeAndDateRange() async throws {
        let harness = FirebaseTestHarness()
        let base = DomainFixtures.referenceDate
        let a = DomainFixtures.workOrder(
            id: WorkOrderID("a"), workType: .installation, priority: .urgent,
            scheduledDate: base, status: .assigned
        )
        let b = DomainFixtures.workOrder(
            id: WorkOrderID("b"), workType: .repair, priority: .urgent,
            scheduledDate: base, status: .assigned
        )
        let c = DomainFixtures.workOrder(
            id: WorkOrderID("c"), workType: .repair, priority: .normal,
            scheduledDate: base.addingTimeInterval(86_400), status: .completed,
            completedAt: base
        )
        for order in [a, b, c] { try await harness.workOrders.save(order) }

        let repairUrgent = try await harness.workOrders.list(
            filter: WorkOrderFilter(priority: .urgent, workType: .repair)
        )
        XCTAssertEqual(repairUrgent.map(\.id), [b.id])

        let window = try await harness.workOrders.list(
            filter: WorkOrderFilter(
                scheduledFrom: base.addingTimeInterval(-60),
                scheduledTo: base.addingTimeInterval(60)
            )
        )
        XCTAssertEqual(Set(window.map(\.id)), Set([a.id, b.id]))
    }

    func testDelete() async throws {
        let harness = FirebaseTestHarness()
        let order = DomainFixtures.workOrder()
        try await harness.workOrders.save(order)
        try await harness.workOrders.delete(id: order.id)
        await XCTAssertThrowsErrorAsync(try await harness.workOrders.fetch(id: order.id)) { _ in }
    }

    func testWriteCoordinatorSavesWorkOrderAndHistoryAtomically() async throws {
        let harness = FirebaseTestHarness()
        let order = DomainFixtures.workOrder(status: .accepted)
        let history = WorkOrderStatusHistory(
            id: "h1",
            workOrderId: order.id,
            fromStatus: .assigned,
            toStatus: .accepted,
            actorUserId: order.assignedTechnicianId,
            occurredAt: DomainFixtures.referenceDate
        )
        try await harness.writeCoordinator.save(workOrder: order, statusHistory: history)

        let fetched = try await harness.workOrders.fetch(id: order.id)
        XCTAssertEqual(fetched, order)
        let listed = try await harness.statusHistory.list(for: order.id)
        XCTAssertEqual(listed, [history])
    }

    func testPredicatesForTechnicianAndOperatorFilters() {
        let technician = UserID("tech-1")
        let techPredicates = FirebaseWorkOrderRepository.predicates(
            for: WorkOrderFilter(assignedTechnicianId: technician)
        )
        XCTAssertEqual(techPredicates, [
            .equal("assignedTechnicianId", .string("tech-1"))
        ])

        let operatorPredicates = FirebaseWorkOrderRepository.predicates(for: .all)
        XCTAssertTrue(operatorPredicates.isEmpty, "operator lists everything — no predicates")
    }
}
