import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianSignatureTests: XCTestCase {

    private var container: DIContainer!
    private var deps: TechnicianDependencies!
    private var tech: User!
    private var customer: Customer!
    private var order: WorkOrder!
    private let signaturePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeTechnicianDependencies()
        tech = DomainFixtures.technicianUser()
        customer = DomainFixtures.customer()
        order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            workType: .installation,
            status: .inProgress
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
    }

    func testCaptureSignaturePersistsMetadataAndLocalBytes() async throws {
        let vm = makeViewModel()
        await vm.load()
        XCTAssertTrue(vm.canCaptureSignature)

        await vm.captureSignature(
            imageData: signaturePNG,
            kind: .technician,
            signerName: nil
        )

        XCTAssertFalse(vm.isCapturingSignature)
        XCTAssertNil(vm.signatureError)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.signatures.count, 1)
        XCTAssertEqual(vm.content?.signatures.first?.kind, .technician)

        let signature = try XCTUnwrap(vm.content?.signatures.first)
        let local = TechnicianLocalMediaStore.loadSignature(
            workOrderId: order.id,
            signatureId: signature.id
        )
        XCTAssertEqual(local, signaturePNG)

        let stored = try await deps.signatureRepository.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
    }

    func testCaptureSignatureEnqueuesSyncCreate() async throws {
        let signature = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .customer,
            imageData: signaturePNG,
            signerName: "Ayşe Yılmaz"
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .signature,
            entityId: signature.id
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create })
        XCTAssertTrue(ops.contains { $0.status == .pending })
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testUnauthorizedTechnicianCannotCaptureSignature() async throws {
        let other = DomainFixtures.technicianUser(
            id: UserID("tech-other"),
            email: "other@example.com",
            fullName: "Other"
        )
        do {
            _ = try await deps.workOrderService.recordSignature(
                actor: other,
                orderId: order.id,
                kind: .technician,
                imageData: signaturePNG
            )
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        let stored = try await deps.signatureRepository.list(for: order.id)
        XCTAssertTrue(stored.isEmpty)
    }

    func testCompletedOrderCannotCaptureSignature() async throws {
        var completed = order!
        completed.status = .completed
        completed.completedAt = DomainFixtures.referenceDate
        try await container.workOrderRepository.save(completed)

        let vm = makeViewModel(orderId: completed.id)
        await vm.load()
        XCTAssertFalse(vm.canCaptureSignature)
        vm.openSignatureSheet()
        XCTAssertFalse(vm.showSignatureSheet)
        XCTAssertNotNil(vm.signatureError)
    }

    func testEmptySignatureRejectedWithoutLeavingLoaded() async throws {
        let vm = makeViewModel()
        await vm.load()
        await vm.captureSignature(imageData: Data(), kind: .technician)

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertNotNil(vm.signatureError)
        XCTAssertTrue(vm.content?.signatures.isEmpty == true)
        XCTAssertFalse(vm.isCapturingSignature)
    }

    func testOfflineSavePersistsLocallyWithPendingSync() async throws {
        let fakeStorage = container.firebaseStorageDataSource as! FakeFirebaseStorageDataSource
        await fakeStorage.setUploadError(FirebaseError.networkUnavailable)
        let vm = makeViewModel()
        await vm.load()
        await vm.captureSignature(imageData: signaturePNG, kind: .customer, signerName: "Müşteri")

        let signature = try XCTUnwrap(vm.content?.signatures.first)
        XCTAssertTrue(signature.isUploadPending || vm.content?.pendingSyncLabel != nil)
        XCTAssertEqual(
            TechnicianLocalMediaStore.loadSignature(workOrderId: order.id, signatureId: signature.id),
            signaturePNG
        )
        XCTAssertEqual(vm.content?.pendingSyncLabel, SyncStatus.pending.technicianDisplayName)
    }

    func testExistingSignaturesDisplayedAfterReload() async throws {
        _ = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: signaturePNG
        )
        let vm = makeViewModel()
        await vm.load()
        XCTAssertEqual(vm.content?.signatures.count, 1)
        XCTAssertEqual(vm.content?.signatures.first?.kind, .technician)

        let signature = try XCTUnwrap(vm.content?.signatures.first)
        XCTAssertEqual(
            TechnicianLocalMediaStore.loadSignature(
                workOrderId: order.id,
                signatureId: signature.id
            ),
            signaturePNG
        )
    }

    func testCaptureCancellationClearsCapturingFlag() async throws {
        let vm = makeViewModel()
        await vm.load()
        let task = Task {
            await vm.captureSignature(imageData: signaturePNG, kind: .technician)
        }
        task.cancel()
        await task.value
        XCTAssertFalse(vm.isCapturingSignature)
        XCTAssertNotEqual(vm.phase, .submitting)
    }

    func testDuplicateSubmissionDoesNotLeaveCapturingOrSubmitting() async throws {
        let vm = makeViewModel()
        await vm.load()
        let first = Task { await vm.captureSignature(imageData: signaturePNG, kind: .technician) }
        let second = Task {
            await vm.captureSignature(
                imageData: signaturePNG,
                kind: .customer,
                signerName: "B"
            )
        }
        await first.value
        await second.value

        XCTAssertFalse(vm.isCapturingSignature)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertNotEqual(vm.phase, .submitting)
        let stored = try await deps.signatureRepository.list(for: order.id)
        XCTAssertGreaterThanOrEqual(stored.count, 1)
        XCTAssertLessThanOrEqual(stored.count, 2)
    }

    func testNotesPhotosAndLocationStillWorkAlongsideSignature() async throws {
        let vm = makeViewModel()
        await vm.load()
        await vm.addNote("Servis notu korundu")
        await vm.addPhoto(imageData: Data([0x11]), category: .before)
        await vm.captureLocation(event: .arrived)
        await vm.captureSignature(imageData: signaturePNG, kind: .technician)

        XCTAssertEqual(vm.content?.notes.count, 1)
        XCTAssertEqual(vm.content?.photos.count, 1)
        XCTAssertEqual(vm.content?.locations.count, 1)
        XCTAssertEqual(vm.content?.signatures.count, 1)
        XCTAssertEqual(vm.phase, .loaded)
    }

    private func makeViewModel(orderId: WorkOrderID? = nil) -> TechnicianWorkOrderDetailViewModel {
        TechnicianWorkOrderDetailViewModel(
            workOrderId: orderId ?? order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: FixedLocationSampler(
                coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 5)
            )
        )
    }
}
