import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianCompleteUIGateTests: XCTestCase {

    private var container: DIContainer!
    private var deps: TechnicianDependencies!
    private var tech: User!
    private var customer: Customer!
    private let fixedCoordinate = LocationCoordinate(latitude: 41.02, longitude: 28.99, accuracy: 5)

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeTechnicianDependencies()
        tech = DomainFixtures.technicianUser()
        customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        try await container.userRepository.save(tech)
    }

    func testMissingGPSDisablesComplete() async throws {
        let order = try await seedInProgressOrder()
        try await seedNotesPhotosSignatures(for: order.id)
        // Only arrived — missing enRoute (and completed is excluded from UI gate)
        try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .arrived,
            coordinate: fixedCoordinate
        )

        let vm = makeViewModel(orderId: order.id)
        await vm.load()

        XCTAssertFalse(vm.canComplete)
        XCTAssertTrue(
            vm.content?.blockingCompletionGaps.contains(.missingLocation(.enRoute)) == true
        )
    }

    func testMissingNoteDisablesComplete() async throws {
        let order = try await seedInProgressOrder()
        try await seedPhotos(for: order.id)
        try await seedEnRouteArrived(for: order.id)
        try await seedSignatures(for: order.id)

        let vm = makeViewModel(orderId: order.id)
        await vm.load()

        XCTAssertFalse(vm.canComplete)
        XCTAssertEqual(vm.content?.blockingCompletionGaps, [.missingNote])
    }

    func testMissingPhotoDisablesComplete() async throws {
        let order = try await seedInProgressOrder()
        _ = try await deps.workOrderService.addNote(
            actor: tech,
            orderId: order.id,
            text: "Not"
        )
        try await seedEnRouteArrived(for: order.id)
        try await seedSignatures(for: order.id)
        _ = try await deps.workOrderService.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: Data([0x01])
        )

        let vm = makeViewModel(orderId: order.id)
        await vm.load()

        XCTAssertFalse(vm.canComplete)
        XCTAssertTrue(
            vm.content?.blockingCompletionGaps.contains(.missingPhoto(.after)) == true
        )
    }

    func testMissingSignatureDisablesComplete() async throws {
        let order = try await seedInProgressOrder()
        try await seedNotesPhotos(for: order.id)
        try await seedEnRouteArrived(for: order.id)
        _ = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: TechnicianPlaceholderImage.pngData
        )

        let vm = makeViewModel(orderId: order.id)
        await vm.load()

        XCTAssertFalse(vm.canComplete)
        XCTAssertEqual(
            vm.content?.blockingCompletionGaps,
            [.missingCustomerSignature]
        )
    }

    func testAllPreCompleteRequirementsEnableCompleteWithoutCompletedGPS() async throws {
        let order = try await seedInProgressOrder()
        try await seedNotesPhotosSignatures(for: order.id)
        try await seedEnRouteArrived(for: order.id)

        let vm = makeViewModel(orderId: order.id)
        await vm.load()

        XCTAssertTrue(vm.canComplete)
        XCTAssertEqual(vm.content?.blockingCompletionGaps, [])
        XCTAssertTrue(
            vm.content?.missingRequirements.contains(.missingLocation(.completed)) == true
        )
    }

    func testDomainCompleteStillRequiresCompletedGPS() async throws {
        let order = try await seedInProgressOrder()
        try await seedNotesPhotosSignatures(for: order.id)
        try await seedEnRouteArrived(for: order.id)

        do {
            _ = try await deps.workOrderService.complete(
                actor: tech,
                orderId: order.id,
                completedLocationId: nil
            )
            XCTFail("domain must still enforce completed GPS")
        } catch let error as DomainError {
            guard case .incompleteWorkOrder(let items) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(items.contains(.missingLocation(.completed)))
        }
    }

    // MARK: - Helpers

    private func makeViewModel(orderId: WorkOrderID) -> TechnicianWorkOrderDetailViewModel {
        TechnicianWorkOrderDetailViewModel(
            workOrderId: orderId,
            actor: tech,
            dependencies: deps,
            locationSampler: FixedLocationSampler(coordinate: fixedCoordinate)
        )
    }

    private func seedInProgressOrder() async throws -> WorkOrder {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            workType: .installation,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)
        return order
    }

    private func seedNotesPhotosSignatures(for orderId: WorkOrderID) async throws {
        try await seedNotesPhotos(for: orderId)
        try await seedSignatures(for: orderId)
    }

    private func seedNotesPhotos(for orderId: WorkOrderID) async throws {
        _ = try await deps.workOrderService.addNote(
            actor: tech,
            orderId: orderId,
            text: "Servis notu"
        )
        try await seedPhotos(for: orderId)
    }

    private func seedPhotos(for orderId: WorkOrderID) async throws {
        for category in PhotoRequirements.requiredCategories(for: .installation) {
            _ = try await deps.workOrderService.addPhoto(
                actor: tech,
                orderId: orderId,
                category: category,
                imageData: Data([0x01, 0x02])
            )
        }
    }

    private func seedSignatures(for orderId: WorkOrderID) async throws {
        _ = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: orderId,
            kind: .technician,
            imageData: TechnicianPlaceholderImage.pngData
        )
        _ = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: orderId,
            kind: .customer,
            imageData: TechnicianPlaceholderImage.pngData,
            signerName: "Müşteri"
        )
    }

    private func seedEnRouteArrived(for orderId: WorkOrderID) async throws {
        _ = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: orderId,
            event: .enRoute,
            coordinate: fixedCoordinate
        )
        _ = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: orderId,
            event: .arrived,
            coordinate: fixedCoordinate
        )
    }
}
