import XCTest
@testable import DonanimOperasyonServis

final class CompleteWorkOrderUseCaseTests: XCTestCase {

    struct Harness {
        let useCase: CompleteWorkOrderUseCase
        let orders: InMemoryWorkOrderRepository
        let history: InMemoryStatusHistoryRepository
    }

    func makeHarness(
        workOrder: WorkOrder,
        notes: [WorkOrderNote],
        photos: [WorkOrderPhoto],
        locations: [WorkOrderLocation],
        signatures: [Signature]
    ) -> Harness {
        let orders = InMemoryWorkOrderRepository(seed: [workOrder])
        let history = InMemoryStatusHistoryRepository()
        let useCase = CompleteWorkOrderUseCase(
            workOrderRepository: orders,
            statusHistoryRepository: history,
            noteRepository: InMemoryNoteRepository(seed: notes),
            photoRepository: InMemoryPhotoRepository(seed: photos),
            locationRepository: InMemoryLocationRepository(seed: locations),
            signatureRepository: InMemorySignatureRepository(seed: signatures)
        )
        return Harness(useCase: useCase, orders: orders, history: history)
    }

    // MARK: - Happy path

    func testCompletesWhenAllRequirementsMet() async throws {
        let tech = DomainFixtures.technicianUser()
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            workType: .repair,
            status: .inProgress
        )
        let ctx = DomainFixtures.fullCompletionContext(for: .repair)
        // Rebind evidence to this specific work order id
        let boundPhotos = ctx.photos.map { photo in
            WorkOrderPhoto(
                id: photo.id,
                workOrderId: inProgress.id,
                category: photo.category,
                storagePath: photo.storagePath,
                capturedByUserId: photo.capturedByUserId,
                capturedAt: photo.capturedAt
            )
        }
        let boundLocations = ctx.locations.map { loc in
            WorkOrderLocation(
                id: loc.id,
                workOrderId: inProgress.id,
                event: loc.event,
                coordinate: loc.coordinate,
                capturedByUserId: loc.capturedByUserId,
                capturedAt: loc.capturedAt
            )
        }
        let boundSignatures = ctx.signatures.map { sig in
            Signature(
                id: sig.id,
                workOrderId: inProgress.id,
                kind: sig.kind,
                storagePath: sig.storagePath,
                signerName: sig.signerName,
                capturedByUserId: sig.capturedByUserId,
                capturedAt: sig.capturedAt
            )
        }
        let boundNotes = ctx.notes.map { note in
            WorkOrderNote(
                id: note.id,
                workOrderId: inProgress.id,
                authorUserId: note.authorUserId,
                text: note.text,
                createdAt: note.createdAt
            )
        }

        let h = makeHarness(
            workOrder: inProgress,
            notes: boundNotes,
            photos: boundPhotos,
            locations: boundLocations,
            signatures: boundSignatures
        )
        let now = DomainFixtures.referenceDate.addingTimeInterval(3_600)

        let completed = try await h.useCase.execute(
            actor: tech,
            orderId: inProgress.id,
            at: now
        )

        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.completedAt, now)
        XCTAssertEqual(completed.updatedAt, now)
        XCTAssertNil(completed.currentPauseReason)

        let entries = await h.history.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.fromStatus, .inProgress)
        XCTAssertEqual(entries.first?.toStatus, .completed)
    }

    // MARK: - Missing requirement gates

    func testMissingRequirementsAreReportedAndOrderIsNotMutated() async throws {
        let tech = DomainFixtures.technicianUser()
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            workType: .installation,
            status: .inProgress
        )
        let h = makeHarness(
            workOrder: inProgress,
            notes: [],
            photos: [],
            locations: [],
            signatures: []
        )

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: tech, orderId: inProgress.id)
        ) { error in
            guard case let .incompleteWorkOrder(missing)? = error as? DomainError else {
                XCTFail("Expected .incompleteWorkOrder, got \(error)")
                return
            }
            let set = Set(missing)
            XCTAssertTrue(set.contains(.missingNote))
            XCTAssertTrue(set.contains(.missingPhoto(.before)))
            XCTAssertTrue(set.contains(.missingPhoto(.after)))
            XCTAssertTrue(set.contains(.missingLocation(.enRoute)))
            XCTAssertTrue(set.contains(.missingLocation(.arrived)))
            XCTAssertTrue(set.contains(.missingLocation(.completed)))
            XCTAssertTrue(set.contains(.missingTechnicianSignature))
            XCTAssertTrue(set.contains(.missingCustomerSignature))
        }

        let stored = try await h.orders.fetch(id: inProgress.id)
        XCTAssertEqual(stored.status, .inProgress, "work order must not be mutated on failure")
        let history = await h.history.all()
        XCTAssertTrue(history.isEmpty, "no history must be written on failure")
    }

    // MARK: - Authorization

    func testCannotCompleteAnotherTechniciansOrder() async {
        let alice = DomainFixtures.technicianUser(id: UserID("tech-alice"))
        let bob = DomainFixtures.technicianUser(id: UserID("tech-bob"))
        let inProgress = DomainFixtures.workOrder(
            assignedTechnicianId: alice.id,
            workType: .installation,
            status: .inProgress
        )
        let h = makeHarness(
            workOrder: inProgress,
            notes: [DomainFixtures.note(workOrderId: inProgress.id)],
            photos: [],
            locations: [],
            signatures: []
        )

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: bob, orderId: inProgress.id)
        ) { error in
            XCTAssertEqual(error as? DomainError, .unauthorized(action: .completeWorkOrder))
        }
    }

    func testCannotCompleteFromInvalidSourceState() async {
        let tech = DomainFixtures.technicianUser()
        let assigned = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .assigned
        )
        let h = makeHarness(
            workOrder: assigned,
            notes: [],
            photos: [],
            locations: [],
            signatures: []
        )

        await XCTAssertThrowsErrorAsync(
            try await h.useCase.execute(actor: tech, orderId: assigned.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidStateTransition(from: .assigned, to: .completed)
            )
        }
    }
}
