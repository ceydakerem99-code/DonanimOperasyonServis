import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class OperatorNotificationLifecycleTests: XCTestCase {

    func testNotificationEmptyLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .empty)
        XCTAssertTrue(vm.notifications.isEmpty)
    }

    func testNotificationLoadedLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)
        try await deps.notificationRepository.save(
            DomainFixtures.notification(recipientUserId: operatorUser.id)
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.notifications.count, 1)
    }

    func testCancellationWhileLoadingSettlesAwayFromSpinner() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        let task = Task { await vm.load() }
        task.cancel()
        await task.value

        XCTAssertNotEqual(vm.phase, .loading)
    }
}

@MainActor
final class OperatorEditRequestLifecycleTests: XCTestCase {

    func testEditRequestEmptyLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorEditRequestListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .empty)
    }

    func testEditRequestFiltersByStatus() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(status: .completed)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await container.workOrderRepository.save(order)

        var pending = DomainFixtures.editRequest(
            id: EditRequestID("er-pending"),
            workOrderId: order.id,
            requestedByUserId: technician.id,
            status: .pending
        )
        let approved = DomainFixtures.editRequest(
            id: EditRequestID("er-approved"),
            workOrderId: order.id,
            requestedByUserId: technician.id,
            status: .approved,
            reviewedByUserId: operatorUser.id,
            reviewedAt: DomainFixtures.referenceDate
        )
        try await deps.editRequestRepository.save(pending)
        try await deps.editRequestRepository.save(approved)

        let vm = OperatorEditRequestListViewModel(actor: operatorUser, dependencies: deps)
        await vm.selectFilter(.pending)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].status, .pending)

        await vm.selectFilter(.approved)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].status, .approved)

        await vm.selectFilter(.all)
        XCTAssertEqual(vm.rows.count, 2)
    }

    func testOrphanedEditRequestDoesNotBlockList() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)
        try await deps.editRequestRepository.save(
            DomainFixtures.editRequest(
                workOrderId: WorkOrderID("missing-wo"),
                requestedByUserId: UserID("missing-user")
            )
        )

        let vm = OperatorEditRequestListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].workOrderNumber, "missing-wo")
    }
}

@MainActor
final class OperatorTimelineHistoryTests: XCTestCase {

    func testDetailTimelineUsesStatusHistoryRepository() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: technician.id,
            customerId: customer.id,
            status: .completed
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        try await deps.statusHistoryRepository.append(
            DomainFixtures.statusHistory(
                id: "h1",
                workOrderId: order.id,
                fromStatus: nil,
                toStatus: .assigned,
                actorUserId: operatorUser.id
            )
        )
        try await deps.statusHistoryRepository.append(
            DomainFixtures.statusHistory(
                id: "h2",
                workOrderId: order.id,
                fromStatus: .assigned,
                toStatus: .completed,
                actorUserId: technician.id
            )
        )

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.timeline.count, 2)
        XCTAssertEqual(vm.content?.timeline.last?.toStatus, .completed)
        XCTAssertEqual(vm.content?.workOrder.status, .completed)
    }

    func testCreateWorkOrderPersistsInitialHistory() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: DomainFixtures.newWorkOrderRequest(
                assignedTechnicianId: technician.id,
                customerId: customer.id
            )
        )
        let history = try await deps.statusHistoryRepository.list(for: created.id)
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.first?.toStatus, .assigned)
    }

    func testDemoSeedBackfillsStatusHistoryForCompletedOrder() async throws {
        let container = DIContainer.mock()
        await DemoAccountSeeder.seedIfNeeded(container: container)

        let history = try await container.workOrderStatusHistoryRepository.list(
            for: WorkOrderID("demo-wo-done")
        )
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.last?.toStatus, .completed)

        // Second seed must not duplicate
        await DemoAccountSeeder.seedIfNeeded(container: container)
        let again = try await container.workOrderStatusHistoryRepository.list(
            for: WorkOrderID("demo-wo-done")
        )
        XCTAssertEqual(again.count, history.count)
    }
}

@MainActor
final class AsyncLoadSettlementTests: XCTestCase {
    func testSettlementPrefersEmptyWhenNoItems() {
        let result = AsyncLoadSettlement.phaseAfterCancellation(
            currentPhaseIsLoading: true,
            itemsEmpty: true,
            loaded: "loaded",
            empty: "empty"
        )
        XCTAssertEqual(result, "empty")
    }

    func testSettlementNilWhenNotLoading() {
        let result = AsyncLoadSettlement.phaseAfterCancellation(
            currentPhaseIsLoading: false,
            itemsEmpty: true,
            loaded: "loaded",
            empty: "empty"
        )
        XCTAssertNil(result)
    }

    func testSettleCancelledLoadUsesSnapshotFromLoadStart() {
        let result = AsyncLoadSettlement.settleCancelledLoad(
            generation: 1,
            currentGeneration: 1,
            phase: "loading",
            loadingPhase: "loading",
            hadCachedContentAtStart: true,
            loadedPhase: "loaded",
            emptyPhase: "empty"
        )
        XCTAssertEqual(result, "loaded")
    }

    func testSettleCancelledLoadIgnoresSupersededGeneration() {
        let result = AsyncLoadSettlement.settleCancelledLoad(
            generation: 1,
            currentGeneration: 2,
            phase: "loading",
            loadingPhase: "loading",
            hadCachedContentAtStart: false,
            loadedPhase: "loaded",
            emptyPhase: "empty"
        )
        XCTAssertNil(result)
    }
}
