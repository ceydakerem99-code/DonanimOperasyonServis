import XCTest
@testable import DonanimOperasyonServis

final class FirebaseEditRequestRepositoryTests: XCTestCase {

    func testSaveFetchListByStatusAndWorkOrder() async throws {
        let harness = FirebaseTestHarness()
        let order = DomainFixtures.workOrder(status: .completed, completedAt: DomainFixtures.referenceDate)
        try await harness.workOrders.save(order)

        let pending = DomainFixtures.editRequest(id: EditRequestID("p"), workOrderId: order.id, status: .pending)
        let approved = DomainFixtures.editRequest(
            id: EditRequestID("a"),
            workOrderId: order.id,
            status: .approved,
            reviewedByUserId: DomainFixtures.operatorUser().id,
            reviewedAt: DomainFixtures.referenceDate
        )
        try await harness.editRequests.save(pending)
        try await harness.editRequests.save(approved)

        let fetched = try await harness.editRequests.fetch(id: pending.id)
        XCTAssertEqual(fetched, pending)
        let pendingList = try await harness.editRequests.listByStatus(.pending)
        XCTAssertEqual(pendingList.map(\.id), [pending.id])
        let all = try await harness.editRequests.list(for: order.id)
        XCTAssertEqual(Set(all.map(\.id)), Set([pending.id, approved.id]))
    }

    func testFetchUnknownThrowsNotFound() async throws {
        let harness = FirebaseTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.editRequests.fetch(id: EditRequestID("missing"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "EditRequest", id: "missing"))
        }
    }
}
