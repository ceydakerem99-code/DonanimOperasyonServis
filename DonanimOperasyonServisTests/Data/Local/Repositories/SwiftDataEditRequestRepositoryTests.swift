import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataEditRequestRepositoryTests: XCTestCase {

    private func seededHarness() async throws -> (SwiftDataTestHarness, WorkOrder) {
        let harness = try SwiftDataTestHarness()
        let order = DomainFixtures.workOrder(
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        try await harness.workOrders.save(order)
        return (harness, order)
    }

    func testSaveThenFetch() async throws {
        let (harness, order) = try await seededHarness()
        let request = DomainFixtures.editRequest(workOrderId: order.id)
        try await harness.editRequests.save(request)

        let fetched = try await harness.editRequests.fetch(id: request.id)
        XCTAssertEqual(fetched, request)
    }

    func testFetchUnknownIdThrowsNotFound() async throws {
        let harness = try SwiftDataTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.editRequests.fetch(id: EditRequestID("missing"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "EditRequest", id: "missing"))
        }
    }

    func testListByWorkOrder() async throws {
        let (harness, order) = try await seededHarness()
        let a = DomainFixtures.editRequest(id: EditRequestID("er-1"), workOrderId: order.id)
        let b = DomainFixtures.editRequest(id: EditRequestID("er-2"), workOrderId: order.id)
        try await harness.editRequests.save(a)
        try await harness.editRequests.save(b)

        let list = try await harness.editRequests.list(for: order.id)
        XCTAssertEqual(Set(list.map(\.id)), Set([a.id, b.id]))
    }

    func testListByStatus() async throws {
        let (harness, order) = try await seededHarness()
        let pending = DomainFixtures.editRequest(id: EditRequestID("p"), workOrderId: order.id, status: .pending)
        let approved = DomainFixtures.editRequest(
            id: EditRequestID("a"),
            workOrderId: order.id,
            status: .approved,
            reviewedByUserId: DomainFixtures.operatorUser().id,
            reviewedAt: DomainFixtures.referenceDate
        )
        let rejected = DomainFixtures.editRequest(
            id: EditRequestID("r"),
            workOrderId: order.id,
            status: .rejected,
            reviewedByUserId: DomainFixtures.operatorUser().id,
            reviewedAt: DomainFixtures.referenceDate
        )
        for request in [pending, approved, rejected] { try await harness.editRequests.save(request) }

        let pendingList = try await harness.editRequests.listByStatus(.pending)
        XCTAssertEqual(pendingList.map(\.id), [pending.id])

        let approvedList = try await harness.editRequests.listByStatus(.approved)
        XCTAssertEqual(approvedList.map(\.id), [approved.id])
    }

    func testUpdateReplacesInPlace() async throws {
        let (harness, order) = try await seededHarness()
        var request = DomainFixtures.editRequest(workOrderId: order.id, status: .pending)
        try await harness.editRequests.save(request)

        request.status = .approved
        request.reviewedByUserId = DomainFixtures.operatorUser().id
        request.reviewedAt = DomainFixtures.referenceDate.addingTimeInterval(300)
        request.decisionNote = "Onaylandı"
        try await harness.editRequests.save(request)

        let all = try await harness.editRequests.list(for: order.id)
        XCTAssertEqual(all.count, 1, "upsert must not duplicate")
        XCTAssertEqual(all.first?.status, .approved)
        XCTAssertEqual(all.first?.decisionNote, "Onaylandı")
    }
}
