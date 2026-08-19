import XCTest
@testable import DonanimOperasyonServis

/// Cross-repository tests for the work-order child records: notes,
/// photos, GPS samples, status history, and signatures. Each test
/// seeds a work order via the parent repository, then exercises the
/// corresponding child repository against it.
final class SwiftDataWorkOrderChildrenTests: XCTestCase {

    private func makeHarnessWithSeededOrder() async throws -> (SwiftDataTestHarness, WorkOrder) {
        let harness = try SwiftDataTestHarness()
        let order = DomainFixtures.workOrder()
        try await harness.workOrders.save(order)
        return (harness, order)
    }

    // MARK: - Notes

    func testNotePersistenceRoundTrip() async throws {
        let (harness, order) = try await makeHarnessWithSeededOrder()
        let note = DomainFixtures.note(id: "n1", workOrderId: order.id, text: "Kablo kontrol edildi")
        try await harness.notes.save(note)

        let notes = try await harness.notes.list(for: order.id)
        XCTAssertEqual(notes, [note])
    }

    func testNoteScopedToOwnWorkOrder() async throws {
        let harness = try SwiftDataTestHarness()
        let orderA = DomainFixtures.workOrder(id: WorkOrderID("wo-A"))
        let orderB = DomainFixtures.workOrder(id: WorkOrderID("wo-B"))
        try await harness.workOrders.save(orderA)
        try await harness.workOrders.save(orderB)

        try await harness.notes.save(
            DomainFixtures.note(id: "na", workOrderId: orderA.id, text: "A")
        )
        try await harness.notes.save(
            DomainFixtures.note(id: "nb", workOrderId: orderB.id, text: "B")
        )

        let notesA = try await harness.notes.list(for: orderA.id)
        let notesB = try await harness.notes.list(for: orderB.id)
        XCTAssertEqual(notesA.map(\.id), ["na"])
        XCTAssertEqual(notesB.map(\.id), ["nb"])
    }

    func testNoteDeletion() async throws {
        let (harness, order) = try await makeHarnessWithSeededOrder()
        try await harness.notes.save(
            DomainFixtures.note(id: "n1", workOrderId: order.id, text: "abc")
        )
        try await harness.notes.delete(id: "n1", for: order.id)
        let remaining = try await harness.notes.list(for: order.id)
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Photos

    func testPhotoPersistenceRoundTrip() async throws {
        let (harness, order) = try await makeHarnessWithSeededOrder()
        let photo = DomainFixtures.photo(id: "p1", workOrderId: order.id, category: .evidenceSerialNumber)
        try await harness.photos.save(photo)

        let photos = try await harness.photos.list(for: order.id)
        XCTAssertEqual(photos, [photo])
    }

    // MARK: - Locations

    func testLocationPersistencePreservesCoordinateAndAccuracy() async throws {
        let (harness, order) = try await makeHarnessWithSeededOrder()
        let location = WorkOrderLocation(
            id: "l1",
            workOrderId: order.id,
            event: .arrived,
            coordinate: LocationCoordinate(latitude: 41.0082, longitude: 28.9784, accuracy: 12.5),
            capturedByUserId: order.assignedTechnicianId,
            capturedAt: DomainFixtures.referenceDate
        )
        try await harness.locations.save(location)

        let locations = try await harness.locations.list(for: order.id)
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations.first, location)
        XCTAssertEqual(locations.first?.coordinate.accuracy, 12.5)
    }

    // MARK: - Status history

    func testStatusHistoryAppendAndListInOrder() async throws {
        let (harness, order) = try await makeHarnessWithSeededOrder()

        let assigned = WorkOrderStatusHistory(
            id: "h1",
            workOrderId: order.id,
            fromStatus: nil,
            toStatus: .assigned,
            actorUserId: order.createdByUserId,
            occurredAt: DomainFixtures.referenceDate
        )
        let accepted = WorkOrderStatusHistory(
            id: "h2",
            workOrderId: order.id,
            fromStatus: .assigned,
            toStatus: .accepted,
            actorUserId: order.assignedTechnicianId,
            occurredAt: DomainFixtures.referenceDate.addingTimeInterval(60)
        )
        let paused = WorkOrderStatusHistory(
            id: "h3",
            workOrderId: order.id,
            fromStatus: .inProgress,
            toStatus: .paused,
            pauseReason: .customerWaiting,
            actorUserId: order.assignedTechnicianId,
            occurredAt: DomainFixtures.referenceDate.addingTimeInterval(120)
        )

        try await harness.statusHistory.append(assigned)
        try await harness.statusHistory.append(accepted)
        try await harness.statusHistory.append(paused)

        let history = try await harness.statusHistory.list(for: order.id)
        XCTAssertEqual(history.map(\.id), ["h1", "h2", "h3"])
        XCTAssertEqual(history[2].pauseReason, .customerWaiting)
    }

    // MARK: - Signatures

    func testTechnicianAndCustomerSignaturesArePersistedSeparately() async throws {
        let (harness, order) = try await makeHarnessWithSeededOrder()
        let tech = DomainFixtures.signature(id: "sig-tech", workOrderId: order.id, kind: .technician)
        let customer = DomainFixtures.signature(
            id: "sig-cust", workOrderId: order.id, kind: .customer, signerName: "Zeynep Kaya"
        )
        try await harness.signatures.save(tech)
        try await harness.signatures.save(customer)

        let signatures = try await harness.signatures.list(for: order.id)
        XCTAssertEqual(signatures.count, 2)
        XCTAssertEqual(Set(signatures.map(\.kind)), Set([.technician, .customer]))
        XCTAssertEqual(signatures.first(where: { $0.kind == .customer })?.signerName, "Zeynep Kaya")
    }
}
