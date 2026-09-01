import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianWorkOrderDetailLifecycleTests: XCTestCase {

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

    func testTechnicianCompletionDoesNotLeaveDetailInLoading() async throws {
        let order = try await seedCompletableOrder()

        let vm = makeViewModel(orderId: order.id)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.status, .inProgress)

        await vm.completeWork()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.status, .completed)
        XCTAssertEqual(vm.content?.pendingSyncLabel, SyncStatus.pending.technicianDisplayName)
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testTechnicianDetailCanNavigateBackDuringCompletion() async throws {
        let order = try await seedCompletableOrder()

        let vm = makeViewModel(orderId: order.id)
        vm.startLoad()
        try await Task.sleep(for: .milliseconds(5))
        vm.stopLoad()

        XCTAssertNotEqual(vm.phase, .loading)

        vm.prepareForAppearance()
        while vm.phase == .loading {
            await Task.yield()
        }

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.id, order.id)
    }

    func testStaleLoadDoesNotRevertCompletedDetail() async throws {
        let order = try await seedCompletableOrder()
        let vm = makeViewModel(orderId: order.id)
        await vm.load()
        XCTAssertEqual(vm.content?.workOrder.status, .inProgress)

        vm.startLoad()
        await vm.completeWork()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.status, .completed)

        while vm.phase == .loading {
            await Task.yield()
        }
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.status, .completed)
    }

    func testShellRefreshDuringCompletionKeepsLoadedCompletedState() async throws {
        let order = try await seedCompletableOrder()
        let cache = TechnicianWorkOrderDetailViewModelCache(
            actor: tech,
            dependencies: deps,
            locationSampler: FixedLocationSampler(coordinate: fixedCoordinate)
        )
        let vm = cache.viewModel(for: order.id)
        await vm.load()

        let completionTask = Task { await vm.completeWork() }
        try await Task.sleep(for: .milliseconds(10))
        _ = cache.viewModel(for: order.id)
        vm.prepareForAppearance()
        await completionTask.value

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.status, .completed)
        XCTAssertNotNil(vm.content?.pendingSyncLabel)
    }

    func testSyncIndicatorClearsAfterQueueSucceeds() async throws {
        let order = try await seedCompletableOrder()
        let vm = makeViewModel(orderId: order.id)
        await vm.load()
        await vm.completeWork()
        XCTAssertNotNil(vm.content?.pendingSyncLabel)

        try await markAllSyncOperationsSucceeded(for: order.id)
        await vm.refreshSyncIndicatorIfNeeded()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.status, .completed)
        XCTAssertNil(vm.content?.pendingSyncLabel)
    }

    private func makeViewModel(orderId: WorkOrderID) -> TechnicianWorkOrderDetailViewModel {
        TechnicianWorkOrderDetailViewModel(
            workOrderId: orderId,
            actor: tech,
            dependencies: deps,
            locationSampler: FixedLocationSampler(coordinate: fixedCoordinate)
        )
    }

    private func seedCompletableOrder() async throws -> WorkOrder {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            workType: .installation,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)

        _ = try await deps.workOrderService.addNote(
            actor: tech,
            orderId: order.id,
            text: "Servis notu"
        )
        _ = try await deps.workOrderService.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: Data([0x01])
        )
        _ = try await deps.workOrderService.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .after,
            imageData: Data([0x02])
        )
        _ = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .enRoute,
            coordinate: fixedCoordinate
        )
        _ = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .arrived,
            coordinate: fixedCoordinate
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
            imageData: TechnicianPlaceholderImage.pngData
        )
        return order
    }

    private func markAllSyncOperationsSucceeded(for orderId: WorkOrderID) async throws {
        let pending = try await deps.syncOperationRepository.fetch(status: .pending)
        for var operation in pending {
            operation.status = try SyncStatusStateMachine.transition(from: .pending, to: .inProgress)
            try await deps.syncOperationRepository.update(operation)
            operation.status = try SyncStatusStateMachine.transition(from: .inProgress, to: .succeeded)
            try await deps.syncOperationRepository.update(operation)
        }
        try await deps.syncOperationRepository.deleteCompleted()
    }
}
