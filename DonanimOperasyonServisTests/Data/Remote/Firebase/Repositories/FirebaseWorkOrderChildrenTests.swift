import XCTest
@testable import DonanimOperasyonServis

final class FirebaseWorkOrderChildrenTests: XCTestCase {

    func testNotePhotoLocationHistorySignatureRoundTrip() async throws {
        let harness = FirebaseTestHarness()
        let order = DomainFixtures.workOrder()
        try await harness.workOrders.save(order)

        let note = DomainFixtures.note(id: "n1", workOrderId: order.id, text: "İlk not")
        let photo = DomainFixtures.photo(id: "p1", workOrderId: order.id, category: .before)
        let location = WorkOrderLocation(
            id: "l1",
            workOrderId: order.id,
            event: .arrived,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 5),
            capturedByUserId: order.assignedTechnicianId,
            capturedAt: DomainFixtures.referenceDate
        )
        let history = WorkOrderStatusHistory(
            id: "h1",
            workOrderId: order.id,
            fromStatus: nil,
            toStatus: .assigned,
            actorUserId: order.createdByUserId,
            occurredAt: DomainFixtures.referenceDate
        )
        let signature = DomainFixtures.signature(
            id: "s1", workOrderId: order.id, kind: .customer, signerName: "Zeynep"
        )

        try await harness.notes.save(note)
        try await harness.photos.save(photo)
        try await harness.locations.save(location)
        try await harness.statusHistory.append(history)
        try await harness.signatures.save(signature)

        let notes = try await harness.notes.list(for: order.id)
        let photos = try await harness.photos.list(for: order.id)
        let locations = try await harness.locations.list(for: order.id)
        let historyList = try await harness.statusHistory.list(for: order.id)
        let signatures = try await harness.signatures.list(for: order.id)
        XCTAssertEqual(notes, [note])
        XCTAssertEqual(photos, [photo])
        XCTAssertEqual(locations, [location])
        XCTAssertEqual(historyList, [history])
        XCTAssertEqual(signatures, [signature])
    }

    func testChildRecordsAreScopedByWorkOrderId() async throws {
        let harness = FirebaseTestHarness()
        let a = DomainFixtures.workOrder(id: WorkOrderID("wo-A"))
        let b = DomainFixtures.workOrder(id: WorkOrderID("wo-B"))
        try await harness.workOrders.save(a)
        try await harness.workOrders.save(b)

        try await harness.notes.save(DomainFixtures.note(id: "na", workOrderId: a.id, text: "A"))
        try await harness.notes.save(DomainFixtures.note(id: "nb", workOrderId: b.id, text: "B"))

        let notesA = try await harness.notes.list(for: a.id)
        let notesB = try await harness.notes.list(for: b.id)
        XCTAssertEqual(notesA.map(\.id), ["na"])
        XCTAssertEqual(notesB.map(\.id), ["nb"])
    }

    func testNoteAndPhotoDeletion() async throws {
        let harness = FirebaseTestHarness()
        let order = DomainFixtures.workOrder()
        try await harness.workOrders.save(order)
        try await harness.notes.save(DomainFixtures.note(id: "n1", workOrderId: order.id, text: "x"))
        try await harness.photos.save(DomainFixtures.photo(id: "p1", workOrderId: order.id, category: .after))

        try await harness.notes.delete(id: "n1", for: order.id)
        try await harness.photos.delete(id: "p1", for: order.id)

        let notes = try await harness.notes.list(for: order.id)
        let photos = try await harness.photos.list(for: order.id)
        XCTAssertTrue(notes.isEmpty)
        XCTAssertTrue(photos.isEmpty)
    }
}
