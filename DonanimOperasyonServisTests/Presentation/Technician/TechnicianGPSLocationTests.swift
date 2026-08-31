import XCTest
import CoreLocation
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianGPSLocationTests: XCTestCase {

    private var container: DIContainer!
    private var deps: TechnicianDependencies!
    private var tech: User!
    private var customer: Customer!
    private var order: WorkOrder!
    private let fixedCoordinate = LocationCoordinate(latitude: 41.015, longitude: 28.98, accuracy: 6)

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

    func testCaptureLocationPersistsAgainstWorkOrder() async throws {
        let vm = makeViewModel()
        await vm.load()
        XCTAssertTrue(vm.canCaptureLocation)

        await vm.captureLocation(event: .arrived)

        XCTAssertFalse(vm.isCapturingLocation)
        XCTAssertNil(vm.locationError)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.locations.count, 1)
        XCTAssertEqual(vm.content?.locations.first?.event, .arrived)
        XCTAssertEqual(vm.content?.locations.first?.coordinate.latitude, fixedCoordinate.latitude)

        let stored = try await deps.workOrderLocationRepository.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
    }

    func testCaptureLocationEnqueuesSyncCreate() async throws {
        let location = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .enRoute,
            coordinate: fixedCoordinate
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderLocation,
            entityId: location.id
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create })
        XCTAssertTrue(ops.contains { $0.status == .pending })
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testUnauthorizedTechnicianCannotCaptureLocation() async throws {
        let other = DomainFixtures.technicianUser(
            id: UserID("tech-other"),
            email: "other@example.com",
            fullName: "Other"
        )
        do {
            _ = try await deps.workOrderService.recordLocation(
                actor: other,
                orderId: order.id,
                event: .arrived,
                coordinate: fixedCoordinate
            )
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        }
        let stored = try await deps.workOrderLocationRepository.list(for: order.id)
        XCTAssertTrue(stored.isEmpty)
    }

    func testCompletedOrderCannotCaptureLocation() async throws {
        var completed = order!
        completed.status = .completed
        completed.completedAt = DomainFixtures.referenceDate
        try await container.workOrderRepository.save(completed)

        let vm = makeViewModel(orderId: completed.id)
        await vm.load()
        XCTAssertFalse(vm.canCaptureLocation)
        vm.openLocationSheet()
        XCTAssertFalse(vm.showLocationSheet)
        XCTAssertNotNil(vm.locationError)
    }

    func testPrepareLocationDeniedSetsErrorWithoutCapturing() async throws {
        let vm = makeViewModel()
        await vm.load()
        let phaseBefore = vm.phase

        let allowed = vm.prepareLocationCapture(
            areServicesEnabled: true,
            authorizationStatus: .denied
        )

        XCTAssertFalse(allowed)
        XCTAssertEqual(vm.locationError, TechnicianLocationAccess.deniedMessage)
        XCTAssertFalse(vm.isCapturingLocation)
        XCTAssertEqual(vm.phase, phaseBefore)
        XCTAssertNotEqual(vm.phase, .submitting)
    }

    func testPermissionDeniedDuringSampleSurfacesError() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: ThrowingLocationSampler(error: .permissionDenied)
        )
        await vm.load()
        await vm.captureLocation(event: .enRoute)

        XCTAssertFalse(vm.isCapturingLocation)
        XCTAssertEqual(vm.locationError, LocationSamplingError.permissionDenied.technicianMessage)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.content?.locations.isEmpty == true)
    }

    func testOfflineSavePersistsLocallyWithPendingSync() async throws {
        let vm = makeViewModel()
        await vm.load()
        await vm.captureLocation(event: .completed)

        let location = try XCTUnwrap(vm.content?.locations.first)
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderLocation,
            entityId: location.id
        )
        XCTAssertFalse(ops.isEmpty)
        XCTAssertEqual(vm.content?.pendingSyncLabel, SyncStatus.pending.technicianDisplayName)

        let stored = try await deps.workOrderLocationRepository.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
    }

    func testExistingLocationsDisplayedAfterReload() async throws {
        _ = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .enRoute,
            coordinate: LocationCoordinate(latitude: 40.9, longitude: 29.1, accuracy: 4)
        )
        let vm = makeViewModel()
        await vm.load()
        XCTAssertEqual(vm.content?.locations.count, 1)
        XCTAssertEqual(vm.content?.locations.first?.event, .enRoute)
    }

    func testCaptureCancellationClearsCapturingFlag() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: DelayedLocationSampler(
                nanoseconds: 2_000_000_000,
                coordinate: fixedCoordinate
            )
        )
        await vm.load()
        let task = Task { await vm.captureLocation(event: .arrived) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value
        XCTAssertFalse(vm.isCapturingLocation)
        XCTAssertNotEqual(vm.phase, .submitting)
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testDuplicateSubmissionIgnoredWhileCapturing() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: DelayedLocationSampler(
                nanoseconds: 300_000_000,
                coordinate: fixedCoordinate
            )
        )
        await vm.load()
        async let first: Void = vm.captureLocation(event: .arrived)
        try await Task.sleep(nanoseconds: 30_000_000)
        await vm.captureLocation(event: .enRoute)
        await first

        let stored = try await deps.workOrderLocationRepository.list(for: order.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.event, .arrived)
        XCTAssertFalse(vm.isCapturingLocation)
    }

    func testNotesAndPhotosStillWorkAlongsideLocation() async throws {
        let vm = makeViewModel()
        await vm.load()
        await vm.addNote("Servis notu korundu")
        await vm.addPhoto(imageData: Data([0x11]), category: .before)
        await vm.captureLocation(event: .arrived)

        XCTAssertEqual(vm.content?.notes.count, 1)
        XCTAssertEqual(vm.content?.photos.count, 1)
        XCTAssertEqual(vm.content?.locations.count, 1)
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testPrepareBlockedWhenServicesDisabled() async throws {
        let vm = makeViewModel()
        await vm.load()
        let allowed = vm.prepareLocationCapture(
            areServicesEnabled: false,
            authorizationStatus: .authorizedWhenInUse
        )
        XCTAssertFalse(allowed)
        XCTAssertEqual(vm.locationError, TechnicianLocationAccess.unavailableMessage)
        XCTAssertFalse(vm.isCapturingLocation)
    }

    private func makeViewModel(orderId: WorkOrderID? = nil) -> TechnicianWorkOrderDetailViewModel {
        TechnicianWorkOrderDetailViewModel(
            workOrderId: orderId ?? order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: FixedLocationSampler(coordinate: fixedCoordinate)
        )
    }
}
