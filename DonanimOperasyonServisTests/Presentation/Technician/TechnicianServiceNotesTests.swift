import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianServiceNotesTests: XCTestCase {

    private var container: DIContainer!
    private var deps: TechnicianDependencies!
    private var tech: User!
    private var customer: Customer!
    private var order: WorkOrder!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeTechnicianDependencies()
        tech = DomainFixtures.technicianUser()
        customer = DomainFixtures.customer()
        order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
    }

    func testAddNotePersistsAgainstWorkOrder() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertTrue(vm.canAddNote)
        XCTAssertEqual(vm.content?.notes.count, 0)

        await vm.addNote("Kart okuyucu değiştirildi")

        XCTAssertFalse(vm.isAddingNote)
        XCTAssertNil(vm.noteError)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.notes.count, 1)
        XCTAssertEqual(vm.content?.notes.first?.text, "Kart okuyucu değiştirildi")
        XCTAssertEqual(vm.content?.notes.first?.workOrderId, order.id)

        let stored = try await deps.workOrderNoteRepository.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
    }

    func testAddNoteEnqueuesSyncCreate() async throws {
        let note = try await deps.workOrderService.addNote(
            actor: tech,
            orderId: order.id,
            text: "Offline not"
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderNote,
            entityId: note.id
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create })
        XCTAssertTrue(ops.contains { $0.status == .pending })
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testEmptyNoteShowsErrorWithoutLeavingLoaded() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        await vm.addNote("   ")

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertNotNil(vm.noteError)
        XCTAssertTrue(vm.content?.notes.isEmpty == true)
        XCTAssertFalse(vm.isAddingNote)
    }

    func testUnauthorizedTechnicianCannotAddNote() async throws {
        let other = DomainFixtures.technicianUser(
            id: UserID("tech-other"),
            email: "other@example.com",
            fullName: "Other Tech"
        )

        do {
            _ = try await deps.workOrderService.addNote(
                actor: other,
                orderId: order.id,
                text: "Kaçak not"
            )
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        }

        let stored = try await deps.workOrderNoteRepository.list(for: order.id)
        XCTAssertTrue(stored.isEmpty)
    }

    func testCompletedOrderCannotAddNote() async throws {
        var completed = order!
        completed.status = .completed
        completed.completedAt = DomainFixtures.referenceDate
        try await container.workOrderRepository.save(completed)

        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: completed.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertFalse(vm.canAddNote)

        vm.openNoteSheet()
        XCTAssertFalse(vm.showNoteSheet)
        XCTAssertNotNil(vm.noteError)
    }

    func testDuplicateAddNoteTapDoesNotLeaveLoading() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        await vm.addNote("İlk not")
        await vm.addNote("İkinci not")

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertFalse(vm.isAddingNote)
        let stored = try await deps.workOrderNoteRepository.list(for: order.id)
        XCTAssertEqual(stored.count, 2)
    }

    func testLoadCancellationSettlesAwayFromSpinner() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        let task = Task { await vm.load() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testPendingNoteSyncLabelSurfacesAfterAdd() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        await vm.addNote("Senkron bekleyen not")

        XCTAssertEqual(vm.content?.pendingSyncLabel, SyncStatus.pending.technicianDisplayName)
    }

    func testExistingNotesRemainAfterReload() async throws {
        _ = try await deps.workOrderService.addNote(
            actor: tech,
            orderId: order.id,
            text: "Mevcut not"
        )

        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertEqual(vm.content?.notes.count, 1)
        XCTAssertEqual(vm.content?.notes.first?.text, "Mevcut not")
    }
}
