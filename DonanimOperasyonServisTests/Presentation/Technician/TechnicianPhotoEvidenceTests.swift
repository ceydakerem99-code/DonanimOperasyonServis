import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianPhotoEvidenceTests: XCTestCase {

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
            workType: .installation,
            status: .inProgress
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
    }

    func testAddPhotoPersistsMetadataAndLocalBytes() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertTrue(vm.canAddPhoto)

        let imageData = Data("jpeg-bytes".utf8)
        await vm.addPhoto(imageData: imageData, category: .before)

        XCTAssertFalse(vm.isAddingPhoto)
        XCTAssertNil(vm.photoError)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.photos.count, 1)
        XCTAssertEqual(vm.content?.photos.first?.category, .before)
        XCTAssertEqual(vm.content?.photos.first?.workOrderId, order.id)

        let photo = try XCTUnwrap(vm.content?.photos.first)
        let local = TechnicianLocalMediaStore.loadPhoto(
            workOrderId: order.id,
            photoId: photo.id
        )
        XCTAssertEqual(local, imageData)

        let stored = try await deps.workOrderPhotoRepository.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
    }

    func testAddPhotoEnqueuesSyncCreate() async throws {
        let photo = try await deps.workOrderService.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .after,
            imageData: Data([0x01, 0x02, 0x03])
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderPhoto,
            entityId: photo.id
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create })
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testEmptyPhotoDataRejectedWithoutLeavingLoaded() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        await vm.addPhoto(imageData: Data(), category: .before)

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertNotNil(vm.photoError)
        XCTAssertTrue(vm.content?.photos.isEmpty == true)
        XCTAssertFalse(vm.isAddingPhoto)
    }

    func testUnauthorizedTechnicianCannotAddPhoto() async throws {
        let other = DomainFixtures.technicianUser(
            id: UserID("tech-other"),
            email: "other@example.com",
            fullName: "Other"
        )
        do {
            _ = try await deps.workOrderService.addPhoto(
                actor: other,
                orderId: order.id,
                category: .before,
                imageData: Data([0x11])
            )
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        let stored = try await deps.workOrderPhotoRepository.list(for: order.id)
        XCTAssertTrue(stored.isEmpty)
    }

    func testCompletedOrderCannotAddPhoto() async throws {
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
        XCTAssertFalse(vm.canAddPhoto)
        vm.openPhotoSheet()
        XCTAssertFalse(vm.showPhotoSheet)
        XCTAssertNotNil(vm.photoError)
    }

    func testPendingSyncLabelAfterPhotoAdd() async throws {
        let fakeStorage = container.firebaseStorageDataSource as! FakeFirebaseStorageDataSource
        await fakeStorage.setUploadError(FirebaseError.networkUnavailable)
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        await vm.addPhoto(imageData: Data([0xAA, 0xBB]), category: .before)

        let photo = try XCTUnwrap(vm.content?.photos.first)
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderPhoto,
            entityId: photo.id
        )
        XCTAssertFalse(ops.isEmpty)
        XCTAssertTrue(photo.isUploadPending)
        XCTAssertEqual(vm.content?.pendingSyncLabel, SyncStatus.pending.technicianDisplayName)
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

    func testExistingPhotosRemainAfterReload() async throws {
        _ = try await deps.workOrderService.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .evidenceSerialNumber,
            imageData: Data([0x22, 0x33])
        )
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertEqual(vm.content?.photos.count, 1)
        XCTAssertEqual(vm.content?.photos.first?.category, .evidenceSerialNumber)
    }

    func testNotesFeatureStillWorksAlongsidePhotos() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        await vm.addNote("Servis notu korundu")
        await vm.addPhoto(imageData: Data([0x44]), category: .after)

        XCTAssertEqual(vm.content?.notes.count, 1)
        XCTAssertEqual(vm.content?.photos.count, 1)
        XCTAssertEqual(vm.phase, .loaded)
    }

    // MARK: - Camera (Faz 12G)

    func testCameraUnavailableSetsErrorWithoutSubmitting() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        let phaseBefore = vm.phase

        let allowed = await vm.prepareCameraCapture(
            isHardwareAvailable: false,
            authorizationStatus: .authorized,
            requestAccess: { true }
        )

        XCTAssertFalse(allowed)
        XCTAssertEqual(vm.photoError, TechnicianCameraAccess.unavailableMessage)
        XCTAssertFalse(vm.isAddingPhoto)
        XCTAssertEqual(vm.phase, phaseBefore)
        XCTAssertNotEqual(vm.phase, .submitting)
    }

    func testCameraDeniedSetsErrorWithoutSubmitting() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()

        let allowed = await vm.prepareCameraCapture(
            isHardwareAvailable: true,
            authorizationStatus: .denied,
            requestAccess: { true }
        )

        XCTAssertFalse(allowed)
        XCTAssertEqual(vm.photoError, TechnicianCameraAccess.deniedMessage)
        XCTAssertFalse(vm.isAddingPhoto)
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testCameraNotDeterminedDeniedAfterPrompt() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()

        let allowed = await vm.prepareCameraCapture(
            isHardwareAvailable: true,
            authorizationStatus: .notDetermined,
            requestAccess: { false }
        )

        XCTAssertFalse(allowed)
        XCTAssertEqual(vm.photoError, TechnicianCameraAccess.deniedMessage)
        XCTAssertFalse(vm.isAddingPhoto)
    }

    func testCameraAuthorizedAllowsPresentation() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()

        let allowed = await vm.prepareCameraCapture(
            isHardwareAvailable: true,
            authorizationStatus: .authorized,
            requestAccess: { XCTFail("should not request"); return false }
        )

        XCTAssertTrue(allowed)
        XCTAssertNil(vm.photoError)
        XCTAssertFalse(vm.isAddingPhoto)
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testCameraCapturedBytesUseSameAddPhotoPath() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        vm.selectPhotoCategory(.evidenceSerialNumber)

        // Simulated camera JPEG bytes → same addPhoto(imageData:) as gallery.
        let cameraJPEG = Data("camera-jpeg-bytes".utf8)
        await vm.addPhoto(imageData: cameraJPEG)

        XCTAssertFalse(vm.isAddingPhoto)
        XCTAssertNil(vm.photoError)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.photos.count, 1)
        XCTAssertEqual(vm.content?.photos.first?.category, .evidenceSerialNumber)

        let photo = try XCTUnwrap(vm.content?.photos.first)
        let local = TechnicianLocalMediaStore.loadPhoto(
            workOrderId: order.id,
            photoId: photo.id
        )
        XCTAssertEqual(local, cameraJPEG)

        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderPhoto,
            entityId: photo.id
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create })
    }

    func testCameraPrepareBlockedOnCompletedOrder() async throws {
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

        let allowed = await vm.prepareCameraCapture(
            isHardwareAvailable: true,
            authorizationStatus: .authorized,
            requestAccess: { true }
        )

        XCTAssertFalse(allowed)
        XCTAssertNotNil(vm.photoError)
        XCTAssertFalse(vm.isAddingPhoto)
    }

    func testAddPhotoCancellationClearsIsAddingPhoto() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        let task = Task {
            await vm.addPhoto(imageData: Data([0xCA, 0xFE]), category: .before)
        }
        task.cancel()
        await task.value
        XCTAssertFalse(vm.isAddingPhoto)
        XCTAssertNotEqual(vm.phase, .submitting)
        XCTAssertNotEqual(vm.phase, .loading)
    }
}
