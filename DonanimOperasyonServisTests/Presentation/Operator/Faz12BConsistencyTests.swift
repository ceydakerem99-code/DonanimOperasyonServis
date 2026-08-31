import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class Faz12BDashboardConsistencyTests: XCTestCase {

    func testDashboardOperationsIncludeAllNonTerminalOrders() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.customerRepository.save(customer)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_720_000_000))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let now = today.addingTimeInterval(10_000)

        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-today"),
                customerId: customer.id,
                scheduledDate: today.addingTimeInterval(3600),
                scheduledTimeRange: ScheduledTimeRange(
                    start: today.addingTimeInterval(3600),
                    end: today.addingTimeInterval(20_000)
                ),
                status: .assigned
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-yesterday"),
                workOrderNumber: "WO-OLD",
                customerId: customer.id,
                scheduledDate: yesterday,
                scheduledTimeRange: nil,
                status: .assigned
            )
        )

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps, calendar: calendar)
        await vm.load(now: now)

        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 2)
        XCTAssertEqual(vm.operationsKPIs.overdueWorkOrders, 1)
    }

    func testActiveStatusHelperMatchesAcceptedThroughInProgress() {
        XCTAssertTrue(WorkOrderPresentationMapping.isActiveStatus(.accepted))
        XCTAssertTrue(WorkOrderPresentationMapping.isActiveStatus(.enRoute))
        XCTAssertTrue(WorkOrderPresentationMapping.isActiveStatus(.arrived))
        XCTAssertTrue(WorkOrderPresentationMapping.isActiveStatus(.inProgress))
        XCTAssertFalse(WorkOrderPresentationMapping.isActiveStatus(.assigned))
        XCTAssertFalse(WorkOrderPresentationMapping.isActiveStatus(.paused))
        XCTAssertFalse(WorkOrderPresentationMapping.isActiveStatus(.completed))
    }

    func testListDevamEdenFilterUsesSharedActiveStatuses() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let tech = DomainFixtures.technicianUser()
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)

        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-accepted"),
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                status: .accepted
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-progress"),
                workOrderNumber: "WO-2",
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                status: .inProgress
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-assigned"),
                workOrderNumber: "WO-3",
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                status: .assigned
            )
        )

        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await vm.selectFilter(.inProgress)

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.cards.count, 2)
        XCTAssertTrue(vm.cards.contains { $0.id == "wo-accepted" })
        XCTAssertTrue(vm.cards.contains { $0.id == "wo-progress" })
    }

    func testUrgentNavigationAppliesPriorityFilter() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let tech = DomainFixtures.technicianUser()
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)

        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-urgent"),
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                priority: .urgent,
                status: .assigned
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-normal"),
                workOrderNumber: "WO-N",
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                priority: .normal,
                status: .assigned
            )
        )

        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await vm.showUrgentPriorityOnly()

        XCTAssertEqual(vm.priorityFilter, .urgent)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.cards.count, 1)
        XCTAssertEqual(vm.cards.first?.id, "wo-urgent")
    }
}

@MainActor
final class Faz12BReportAttachmentTests: XCTestCase {

    func testReportAttachmentCountsFromRepositories() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .completed
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        try await deps.workOrderPhotoRepository.save(
            DomainFixtures.photo(workOrderId: order.id, category: .before)
        )
        try await deps.workOrderLocationRepository.save(
            DomainFixtures.location(workOrderId: order.id, event: .arrived)
        )
        try await deps.signatureRepository.save(
            DomainFixtures.signature(workOrderId: order.id, kind: .customer)
        )

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.photoCount, 1)
        XCTAssertEqual(vm.content?.locationCount, 1)
        XCTAssertEqual(vm.content?.signatureCount, 1)
    }

    func testEditActiveDoesNotOfferEditRequestNavigation() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        vm.attemptEdit()

        XCTAssertFalse(vm.offersEditRequestNavigation)
        XCTAssertTrue(vm.editBlockedMessage?.contains("doğrudan düzenlenemez") == true)
    }

    func testTrackingDestinationIsReachable() {
        let destination = OperatorDestination.tracking(WorkOrderID("wo-x"))
        XCTAssertEqual(destination.title, "Saha Takibi")
    }
}

@MainActor
final class Faz12BNotificationLifecycleRegressionTests: XCTestCase {

    func testNotificationLifecycleEmptyLoadedAndCancel() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let emptyVM = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await emptyVM.load()
        XCTAssertEqual(emptyVM.phase, .empty)

        try await deps.notificationRepository.save(
            DomainFixtures.notification(recipientUserId: operatorUser.id)
        )
        await emptyVM.load()
        XCTAssertEqual(emptyVM.phase, .loaded)

        let cancelVM = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        let task = Task { await cancelVM.load() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(cancelVM.phase, .loading)
    }
}
