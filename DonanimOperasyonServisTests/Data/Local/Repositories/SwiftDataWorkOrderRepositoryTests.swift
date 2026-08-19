import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataWorkOrderRepositoryTests: XCTestCase {

    // MARK: - CRUD

    func testSaveThenFetchRoundTripsFullValue() async throws {
        let harness = try SwiftDataTestHarness()
        let order = DomainFixtures.workOrder(
            issueDescription: "POS kablosu değiştirilecek",
            priority: .urgent,
            status: .assigned,
            currentPauseReason: nil,
            completedAt: nil
        )
        try await harness.workOrders.save(order)
        let fetched = try await harness.workOrders.fetch(id: order.id)
        XCTAssertEqual(fetched, order)
    }

    func testFetchUnknownIdThrowsNotFound() async throws {
        let harness = try SwiftDataTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.workOrders.fetch(id: WorkOrderID("nope"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "WorkOrder", id: "nope"))
        }
    }

    func testUpsertReplacesExistingWithoutCreatingDuplicate() async throws {
        let harness = try SwiftDataTestHarness()
        var order = DomainFixtures.workOrder(status: .assigned)
        try await harness.workOrders.save(order)

        order.status = .accepted
        order.updatedAt = DomainFixtures.referenceDate.addingTimeInterval(60)
        try await harness.workOrders.save(order)

        let all = try await harness.workOrders.list(filter: .all)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .accepted)
    }

    func testDeleteRemovesWorkOrder() async throws {
        let harness = try SwiftDataTestHarness()
        let order = DomainFixtures.workOrder()
        try await harness.workOrders.save(order)
        try await harness.workOrders.delete(id: order.id)

        await XCTAssertThrowsErrorAsync(
            try await harness.workOrders.fetch(id: order.id)
        ) { _ in }
    }

    // MARK: - Filtering

    func testFilterByAssignedTechnician() async throws {
        let harness = try SwiftDataTestHarness()
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

    func testFilterByStatusAndPriorityAndWorkType() async throws {
        let harness = try SwiftDataTestHarness()

        let a = DomainFixtures.workOrder(
            id: WorkOrderID("a"), workType: .installation, priority: .urgent, status: .assigned
        )
        let b = DomainFixtures.workOrder(
            id: WorkOrderID("b"), workType: .repair, priority: .urgent, status: .assigned
        )
        let c = DomainFixtures.workOrder(
            id: WorkOrderID("c"), workType: .repair, priority: .normal, status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        for order in [a, b, c] { try await harness.workOrders.save(order) }

        let repairUrgent = try await harness.workOrders.list(
            filter: WorkOrderFilter(priority: .urgent, workType: .repair)
        )
        XCTAssertEqual(repairUrgent.map(\.id), [b.id])

        let completed = try await harness.workOrders.list(
            filter: WorkOrderFilter(status: .completed)
        )
        XCTAssertEqual(completed.map(\.id), [c.id])
    }

    func testScheduledDateRangeFilter() async throws {
        let harness = try SwiftDataTestHarness()
        let base = DomainFixtures.referenceDate
        let past = DomainFixtures.workOrder(id: WorkOrderID("past"), scheduledDate: base.addingTimeInterval(-86_400))
        let today = DomainFixtures.workOrder(id: WorkOrderID("today"), scheduledDate: base)
        let future = DomainFixtures.workOrder(id: WorkOrderID("future"), scheduledDate: base.addingTimeInterval(86_400))
        for order in [past, today, future] { try await harness.workOrders.save(order) }

        let window = try await harness.workOrders.list(
            filter: WorkOrderFilter(
                scheduledFrom: base.addingTimeInterval(-3_600),
                scheduledTo: base.addingTimeInterval(3_600)
            )
        )
        XCTAssertEqual(window.map(\.id), [today.id])
    }

    // MARK: - Cascade delete

    func testDeletingWorkOrderCascadesToChildren() async throws {
        let harness = try SwiftDataTestHarness()
        let order = DomainFixtures.workOrder()
        try await harness.workOrders.save(order)

        try await harness.notes.save(
            DomainFixtures.note(id: "n1", workOrderId: order.id, text: "İlk not")
        )
        try await harness.photos.save(
            DomainFixtures.photo(id: "p1", workOrderId: order.id, category: .before)
        )
        try await harness.locations.save(
            DomainFixtures.location(id: "l1", workOrderId: order.id, event: .enRoute)
        )
        try await harness.signatures.save(
            DomainFixtures.signature(id: "s1", workOrderId: order.id, kind: .technician)
        )

        try await harness.workOrders.delete(id: order.id)

        let notes = try await harness.notes.list(for: order.id)
        let photos = try await harness.photos.list(for: order.id)
        let locations = try await harness.locations.list(for: order.id)
        let signatures = try await harness.signatures.list(for: order.id)

        XCTAssertTrue(notes.isEmpty, "cascade delete should remove notes")
        XCTAssertTrue(photos.isEmpty, "cascade delete should remove photos")
        XCTAssertTrue(locations.isEmpty, "cascade delete should remove locations")
        XCTAssertTrue(signatures.isEmpty, "cascade delete should remove signatures")
    }
}
