import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class LocationSamplingTimeoutTests: XCTestCase {

    private var container: DIContainer!
    private var deps: TechnicianDependencies!
    private var tech: User!
    private var order: WorkOrder!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeTechnicianDependencies()
        tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .accepted
        )
        try await deps.customerRepository.save(customer)
        try await container.userRepository.save(tech)
        try await container.workOrderRepository.save(order)
    }

    func testTimedOutErrorHasTurkishMessage() {
        XCTAssertEqual(
            LocationSamplingError.timedOut.technicianMessage,
            "Konum alınamadı. Lütfen GPS'in açık olduğundan emin olun ve tekrar deneyin."
        )
    }

    func testTimeoutDuringDepartDoesNotChangeStatus() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: ThrowingLocationSampler(error: .timedOut)
        )
        await vm.load()
        XCTAssertEqual(vm.content?.workOrder.status, .accepted)

        await vm.performPrimaryAction()

        XCTAssertEqual(vm.phase, .error(LocationSamplingError.timedOut.technicianMessage))
        let stored = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(stored.status, .accepted)
        let locations = try await deps.workOrderLocationRepository.list(for: order.id)
        XCTAssertTrue(locations.isEmpty)
    }

    func testTimeoutDuringCompleteDoesNotCompleteOrder() async throws {
        var inProgress = order!
        inProgress.status = .inProgress
        try await container.workOrderRepository.save(inProgress)

        // Minimal evidence so UI would allow complete; GPS timedOut blocks.
        _ = try await deps.workOrderService.addNote(
            actor: tech,
            orderId: order.id,
            text: "Not"
        )
        for category in PhotoRequirements.requiredCategories(for: .installation) {
            _ = try await deps.workOrderService.addPhoto(
                actor: tech,
                orderId: order.id,
                category: category,
                imageData: Data([0x01])
            )
        }
        let coord = LocationCoordinate(latitude: 41, longitude: 29, accuracy: 3)
        _ = try await deps.workOrderService.recordLocation(
            actor: tech, orderId: order.id, event: .enRoute, coordinate: coord
        )
        _ = try await deps.workOrderService.recordLocation(
            actor: tech, orderId: order.id, event: .arrived, coordinate: coord
        )
        _ = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: TechnicianPlaceholderImage.pngData
        )
        _ = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .customer,
            imageData: TechnicianPlaceholderImage.pngData,
            signerName: "Müşteri"
        )

        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: ThrowingLocationSampler(error: .timedOut)
        )
        await vm.load()
        XCTAssertTrue(vm.canComplete)

        await vm.completeWork()

        XCTAssertEqual(vm.phase, .error(LocationSamplingError.timedOut.technicianMessage))
        let stored = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(stored.status, .inProgress)
        let locations = try await deps.workOrderLocationRepository.list(for: order.id)
        XCTAssertFalse(locations.contains { $0.event == .completed })
    }

    func testPermissionDeniedStillSurfacesCorrectError() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: ThrowingLocationSampler(error: .permissionDenied)
        )
        await vm.load()
        await vm.performPrimaryAction()

        XCTAssertEqual(
            vm.phase,
            .error(LocationSamplingError.permissionDenied.technicianMessage)
        )
        let stored = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(stored.status, .accepted)
    }

    func testServicesDisabledStillSurfacesCorrectError() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: ThrowingLocationSampler(error: .servicesDisabled)
        )
        await vm.load()
        await vm.performPrimaryAction()

        XCTAssertEqual(
            vm.phase,
            .error(LocationSamplingError.servicesDisabled.technicianMessage)
        )
        let stored = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(stored.status, .accepted)
    }

    func testRetryAfterTimeoutCanSucceed() async throws {
        let coord = LocationCoordinate(latitude: 40.9, longitude: 29.1, accuracy: 4)
        let sampler = ToggleLocationSampler(
            firstError: .timedOut,
            successCoordinate: coord
        )
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: sampler
        )
        await vm.load()

        await vm.performPrimaryAction()
        XCTAssertEqual(vm.phase, .error(LocationSamplingError.timedOut.technicianMessage))
        let afterTimeout = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(afterTimeout.status, .accepted)

        await vm.performPrimaryAction()
        XCTAssertEqual(vm.phase, .loaded)
        let afterRetry = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(afterRetry.status, .enRoute)
        let locations = try await deps.workOrderLocationRepository.list(for: order.id)
        XCTAssertEqual(locations.first?.event, .enRoute)
    }
}

/// First sample throws; subsequent samples succeed.
actor ToggleLocationSampler: LocationSampling {
    let firstError: LocationSamplingError
    let successCoordinate: LocationCoordinate
    private var didFailOnce = false

    init(firstError: LocationSamplingError, successCoordinate: LocationCoordinate) {
        self.firstError = firstError
        self.successCoordinate = successCoordinate
    }

    func sample() async throws -> LocationCoordinate {
        if !didFailOnce {
            didFailOnce = true
            throw firstError
        }
        return successCoordinate
    }
}
