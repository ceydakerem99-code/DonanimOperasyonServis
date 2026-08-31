import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class OperatorDashboardOperationsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let referenceDate = DomainFixtures.referenceDate

    private func makeOrder(
        id: String = "wo-1",
        technicianId: UserID = UserID("tech-1"),
        priority: WorkOrderPriority = .normal,
        scheduledDate: Date? = nil,
        scheduledTimeRange: ScheduledTimeRange? = nil,
        status: WorkOrderStatus = .assigned
    ) -> WorkOrder {
        DomainFixtures.workOrder(
            id: WorkOrderID(id),
            assignedTechnicianId: technicianId,
            priority: priority,
            scheduledDate: scheduledDate ?? referenceDate,
            scheduledTimeRange: scheduledTimeRange,
            status: status
        )
    }

    func testDashboardCountsOpenWorkOrders() {
        let orders = [
            makeOrder(status: .assigned),
            makeOrder(id: "wo-2", status: .completed),
            makeOrder(id: "wo-3", status: .rejected)
        ]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.openWorkOrders, 1)
    }

    func testDashboardCountsUrgentWorkOrders() {
        let orders = [
            makeOrder(priority: .urgent, status: .assigned),
            makeOrder(id: "wo-2", priority: .urgent, status: .completed),
            makeOrder(id: "wo-3", priority: .normal, status: .inProgress)
        ]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.urgentWorkOrders, 1)
    }

    func testDashboardCountsOverdueWorkOrders() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate)!
        let orders = [
            makeOrder(id: "wo-overdue", scheduledDate: yesterday),
            makeOrder(id: "wo-today", scheduledDate: referenceDate)
        ]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.overdueWorkOrders, 1)
    }

    func testDashboardCountsPausedWorkOrders() {
        let orders = [
            makeOrder(status: .paused),
            makeOrder(id: "wo-2", status: .assigned)
        ]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.pausedWorkOrders, 1)
    }

    func testDashboardCountsAvailableTechnicians() {
        let techAvailable = DomainFixtures.technicianUser(id: UserID("tech-a"), fullName: "Available Tech")
        let techBusy = DomainFixtures.technicianUser(id: UserID("tech-b"), fullName: "Busy Tech")
        let orders = [
            makeOrder(id: "wo-1", technicianId: techBusy.id, status: .inProgress)
        ]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [techAvailable, techBusy],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.availableTechnicians, 1)
        XCTAssertEqual(kpis.busyTechnicians, 1)
    }

    func testDashboardCountsBusyTechnicians() {
        let tech = DomainFixtures.technicianUser(id: UserID("tech-busy"))
        let orders = [makeOrder(technicianId: tech.id, status: .enRoute)]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [tech],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.busyTechnicians, 1)
        XCTAssertEqual(kpis.availableTechnicians, 0)
    }

    func testDashboardUsesTechnicianAssignmentSemantics() {
        let tech = DomainFixtures.technicianUser(id: UserID("tech-paused"))
        let orders = [makeOrder(technicianId: tech.id, status: .paused)]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [tech],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(
            TechnicianAssignmentSupport.workingStatus(for: tech.id, orders: orders),
            .available
        )
        XCTAssertEqual(kpis.availableTechnicians, 1)
        XCTAssertEqual(kpis.busyTechnicians, 0)
        XCTAssertEqual(kpis.pausedWorkOrders, 1)
    }

    func testDashboardDoesNotCountCompletedAsOpen() {
        let orders = [makeOrder(status: .completed)]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.openWorkOrders, 0)
    }

    func testDashboardHandlesEmptyData() {
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: [],
            technicians: [],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.openWorkOrders, 0)
        XCTAssertEqual(kpis.urgentWorkOrders, 0)
        XCTAssertEqual(kpis.overdueWorkOrders, 0)
        XCTAssertEqual(kpis.pausedWorkOrders, 0)
        XCTAssertEqual(kpis.availableTechnicians, 0)
        XCTAssertEqual(kpis.busyTechnicians, 0)
    }

    func testOverdueUsesScheduledTimeRangeEnd() {
        let end = referenceDate.addingTimeInterval(-300)
        let start = end.addingTimeInterval(-3600)
        let order = makeOrder(
            scheduledDate: start,
            scheduledTimeRange: ScheduledTimeRange(start: start, end: end)
        )
        XCTAssertTrue(OperatorDashboardOperations.isOverdue(order, now: referenceDate, calendar: calendar))
    }

    func testTodayJobWithoutTimeRangeIsNotOverdue() {
        let order = makeOrder(scheduledDate: referenceDate)
        XCTAssertFalse(OperatorDashboardOperations.isOverdue(order, now: referenceDate, calendar: calendar))
    }

    func testDashboardAvailableTechniciansShowsNames() {
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"), fullName: "Mehmet Kerem")
        let techB = DomainFixtures.technicianUser(id: UserID("tech-b"), fullName: "Ahmet Yılmaz")
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: [],
            technicians: [techA, techB],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.availableTechnicians, 2)
        XCTAssertEqual(kpis.availableTechnicianPreview.previewNames, ["Ahmet Yılmaz", "Mehmet Kerem"])
        XCTAssertEqual(kpis.availableTechnicianPreview.overflowCount, 0)
    }

    func testDashboardBusyTechniciansShowsNames() {
        let tech = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Burak Şahin")
        let orders = [makeOrder(technicianId: tech.id, status: .inProgress)]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [tech],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.busyTechnicians, 1)
        XCTAssertEqual(kpis.busyTechnicianPreview.previewNames, ["Burak Şahin"])
    }

    func testDashboardPausedWorkOrderTechnicianCountsAsAvailable() {
        let tech = DomainFixtures.technicianUser(id: UserID("tech-paused"), fullName: "Ayşe Demir")
        let orders = [makeOrder(technicianId: tech.id, status: .paused)]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [tech],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.availableTechnicians, 1)
        XCTAssertEqual(kpis.availableTechnicianPreview.previewNames, ["Ayşe Demir"])
    }

    func testDashboardTechnicianOverflowCount() {
        let technicians = (0..<5).map { index in
            DomainFixtures.technicianUser(
                id: UserID("tech-\(index)"),
                fullName: "Teknisyen \(index)"
            )
        }
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: [],
            technicians: technicians,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.availableTechnicians, 5)
        XCTAssertEqual(kpis.availableTechnicianPreview.previewNames.count, 2)
        XCTAssertEqual(kpis.availableTechnicianPreview.overflowCount, 3)
    }

    func testDashboardTechnicianNamesUseAssignmentSemantics() {
        let available = DomainFixtures.technicianUser(id: UserID("tech-available"), fullName: "Müsait Tech")
        let busy = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Meşgul Tech")
        let paused = DomainFixtures.technicianUser(id: UserID("tech-paused"), fullName: "Bekleyen Tech")
        let orders = [
            makeOrder(id: "wo-busy", technicianId: busy.id, status: .enRoute),
            makeOrder(id: "wo-paused", technicianId: paused.id, status: .paused)
        ]
        let kpis = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: [available, busy, paused],
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(kpis.availableTechnicianPreview.previewNames, ["Bekleyen Tech", "Müsait Tech"])
        XCTAssertEqual(kpis.busyTechnicianPreview.previewNames, ["Meşgul Tech"])
    }
}

@MainActor
final class OperatorDashboardViewModelOperationsTests: XCTestCase {

    func testDashboardUpdatesAfterWorkOrderStatusChange() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        var order = DomainFixtures.workOrder(
            assignedTechnicianId: technician.id,
            customerId: customer.id,
            priority: .urgent,
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 1)
        XCTAssertEqual(vm.operationsKPIs.urgentWorkOrders, 1)

        order.status = .completed
        order.completedAt = Date()
        try await container.workOrderRepository.save(order)
        await vm.refreshFromLocalCache()

        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 0)
        XCTAssertEqual(vm.operationsKPIs.urgentWorkOrders, 0)
    }

    func testDashboardUsesLocalCacheOffline() async throws {
        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await container.userRepository.save(operatorUser)
        try await container.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, status: .assigned)
        )

        let reachability = FakeNetworkReachability(isReachable: false)
        let baseDeps = container.makeOperatorDependencies()
        let deps = OperatorDependencies(
            getWorkOrders: baseDeps.getWorkOrders,
            getWorkOrder: baseDeps.getWorkOrder,
            workOrderService: baseDeps.workOrderService,
            customerService: baseDeps.customerService,
            workOrderTemplateService: baseDeps.workOrderTemplateService,
            customerRepository: baseDeps.customerRepository,
            userRepository: baseDeps.userRepository,
            localDirectoryCacheRefresh: baseDeps.localDirectoryCacheRefresh,
            workOrderNoteRepository: baseDeps.workOrderNoteRepository,
            workOrderPhotoRepository: baseDeps.workOrderPhotoRepository,
            workOrderLocationRepository: baseDeps.workOrderLocationRepository,
            signatureRepository: baseDeps.signatureRepository,
            statusHistoryRepository: baseDeps.statusHistoryRepository,
            editRequestRepository: baseDeps.editRequestRepository,
            editRequestService: baseDeps.editRequestService,
            customerSatisfactionRepository: baseDeps.customerSatisfactionRepository,
            customerSatisfactionService: baseDeps.customerSatisfactionService,
            notificationRepository: baseDeps.notificationRepository,
            syncOperationRepository: baseDeps.syncOperationRepository,
            syncConflictRepository: baseDeps.syncConflictRepository,
            conflictResolver: baseDeps.conflictResolver,
            networkReachability: reachability,
            profileAccountService: baseDeps.profileAccountService,
            storageDataSource: baseDeps.storageDataSource
        )

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, OperatorDashboardViewModel.Phase.loaded)
        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 1)
    }

    func testDashboardDoesNotCreateNPlusOneFetches() async throws {
        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await container.userRepository.save(operatorUser)
        try await container.userRepository.save(technician)
        try await container.customerRepository.save(customer)

        for index in 0..<5 {
            try await container.workOrderRepository.save(
                DomainFixtures.workOrder(
                    id: WorkOrderID("wo-kpi-\(index)"),
                    workOrderNumber: "WO-KPI-\(index)",
                    assignedTechnicianId: technician.id,
                    customerId: customer.id,
                    priority: index == 0 ? .urgent : .normal,
                    status: .assigned
                )
            )
        }

        let reachability = FakeNetworkReachability(isReachable: false)

        let countingCustomers = CountingListCustomerRepository(inner: container.customerRepository)
        let countingUsers = CountingListUserRepository(inner: container.userRepository)
        let countingWorkOrders = CountingListWorkOrderRepository(inner: container.workOrderRepository)

        let baseDeps = container.makeOperatorDependencies()
        let deps = OperatorDependencies(
            getWorkOrders: GetWorkOrdersUseCase(workOrderRepository: countingWorkOrders),
            getWorkOrder: baseDeps.getWorkOrder,
            workOrderService: baseDeps.workOrderService,
            customerService: baseDeps.customerService,
            workOrderTemplateService: baseDeps.workOrderTemplateService,
            customerRepository: countingCustomers,
            userRepository: countingUsers,
            localDirectoryCacheRefresh: baseDeps.localDirectoryCacheRefresh,
            workOrderNoteRepository: baseDeps.workOrderNoteRepository,
            workOrderPhotoRepository: baseDeps.workOrderPhotoRepository,
            workOrderLocationRepository: baseDeps.workOrderLocationRepository,
            signatureRepository: baseDeps.signatureRepository,
            statusHistoryRepository: baseDeps.statusHistoryRepository,
            editRequestRepository: baseDeps.editRequestRepository,
            editRequestService: baseDeps.editRequestService,
            customerSatisfactionRepository: baseDeps.customerSatisfactionRepository,
            customerSatisfactionService: baseDeps.customerSatisfactionService,
            notificationRepository: baseDeps.notificationRepository,
            syncOperationRepository: baseDeps.syncOperationRepository,
            syncConflictRepository: baseDeps.syncConflictRepository,
            conflictResolver: baseDeps.conflictResolver,
            networkReachability: reachability,
            profileAccountService: baseDeps.profileAccountService,
            storageDataSource: baseDeps.storageDataSource
        )

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let workOrderListCount = await countingWorkOrders.listCallCount
        let customerListCount = await countingCustomers.listCallCount
        let technicianListCount = await countingUsers.listCallCount

        XCTAssertEqual(workOrderListCount, 1)
        XCTAssertLessThanOrEqual(customerListCount, 1)
        XCTAssertLessThanOrEqual(technicianListCount, 1)
        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 5)
    }

    func testDashboardAvailableTapFiltersTechnicians() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let available = DomainFixtures.technicianUser(id: UserID("tech-available"), fullName: "Available Tech")
        let busy = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Busy Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(available)
        try await deps.userRepository.save(busy)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(assignedTechnicianId: busy.id, customerId: customer.id, status: .inProgress)
        )

        let vm = OperatorTechnicianListViewModel(actor: operatorUser, dependencies: deps)
        await vm.applyDashboardScope(.available)

        XCTAssertEqual(vm.selectedFilter, .available)
        XCTAssertEqual(vm.dashboardScope, .available)
        XCTAssertEqual(vm.rows.map(\.fullName), ["Available Tech"])
    }

    func testDashboardBusyTapFiltersTechnicians() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let available = DomainFixtures.technicianUser(id: UserID("tech-available"), fullName: "Available Tech")
        let busy = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Busy Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(available)
        try await deps.userRepository.save(busy)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(assignedTechnicianId: busy.id, customerId: customer.id, status: .enRoute)
        )

        let vm = OperatorTechnicianListViewModel(actor: operatorUser, dependencies: deps)
        await vm.applyDashboardScope(.busy)

        XCTAssertEqual(vm.selectedFilter, .busy)
        XCTAssertEqual(vm.rows.map(\.fullName), ["Busy Tech"])
    }

    func testDashboardPausedTapFiltersTechnicians() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let paused = DomainFixtures.technicianUser(id: UserID("tech-paused"), fullName: "Paused Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(paused)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(assignedTechnicianId: paused.id, customerId: customer.id, status: .paused)
        )

        let vm = OperatorTechnicianListViewModel(actor: operatorUser, dependencies: deps)
        await vm.applyDashboardScope(.available)

        XCTAssertEqual(vm.selectedFilter, .available)
        XCTAssertEqual(vm.rows.map(\.fullName), ["Paused Tech"])
    }

    func testShowAllTechniciansClearsDashboardScope() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser(fullName: "Listed Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let vm = OperatorTechnicianListViewModel(actor: operatorUser, dependencies: deps)
        await vm.applyDashboardScope(.available)
        await vm.clearDashboardScope()

        XCTAssertEqual(vm.selectedFilter, .all)
        XCTAssertEqual(vm.dashboardScope, .none)
        XCTAssertEqual(vm.rows.map(\.fullName), ["Listed Tech"])
    }

    func testDashboardTechnicianStatusCountsMatchOperationsKPIs() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let available = DomainFixtures.technicianUser(id: UserID("tech-available"), fullName: "Available Tech")
        let busy = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Busy Tech")
        let paused = DomainFixtures.technicianUser(id: UserID("tech-paused"), fullName: "Paused Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(available)
        try await deps.userRepository.save(busy)
        try await deps.userRepository.save(paused)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-open"),
                assignedTechnicianId: busy.id,
                customerId: customer.id,
                priority: .urgent,
                status: .assigned
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-busy"),
                assignedTechnicianId: busy.id,
                customerId: customer.id,
                status: .inProgress
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-paused"),
                assignedTechnicianId: paused.id,
                customerId: customer.id,
                status: .paused
            )
        )

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 3)
        XCTAssertEqual(vm.operationsKPIs.urgentWorkOrders, 1)
        XCTAssertEqual(vm.operationsKPIs.pausedWorkOrders, 1)
        XCTAssertEqual(vm.operationsKPIs.availableTechnicians, 2)
        XCTAssertEqual(vm.operationsKPIs.busyTechnicians, 1)
    }

    func testDashboardStatePreservedAfterTechnicianScopeNavigation() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let available = DomainFixtures.technicianUser(id: UserID("tech-available"), fullName: "Available Tech")
        let busy = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Busy Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(available)
        try await deps.userRepository.save(busy)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                assignedTechnicianId: busy.id,
                customerId: customer.id,
                status: .inProgress
            )
        )

        let dashboardVM = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await dashboardVM.load()
        let initialKPIs = dashboardVM.operationsKPIs

        let technicianListVM = OperatorTechnicianListViewModel(actor: operatorUser, dependencies: deps)
        await technicianListVM.applyDashboardScope(.available)
        await dashboardVM.refreshFromLocalCache()

        XCTAssertEqual(dashboardVM.operationsKPIs, initialKPIs)
        XCTAssertEqual(technicianListVM.selectedFilter, .available)
    }

    func testDashboardTechnicianIdentityDoesNotCreateNPlusOneFetches() async throws {
        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await container.userRepository.save(operatorUser)
        try await container.customerRepository.save(customer)

        for index in 0..<4 {
            let tech = DomainFixtures.technicianUser(
                id: UserID("tech-identity-\(index)"),
                fullName: "Tech \(index)"
            )
            try await container.userRepository.save(tech)
        }

        let reachability = FakeNetworkReachability(isReachable: false)
        let countingUsers = CountingListUserRepository(inner: container.userRepository)
        let countingWorkOrders = CountingListWorkOrderRepository(inner: container.workOrderRepository)
        let baseDeps = container.makeOperatorDependencies()
        let deps = OperatorDependencies(
            getWorkOrders: GetWorkOrdersUseCase(workOrderRepository: countingWorkOrders),
            getWorkOrder: baseDeps.getWorkOrder,
            workOrderService: baseDeps.workOrderService,
            customerService: baseDeps.customerService,
            workOrderTemplateService: baseDeps.workOrderTemplateService,
            customerRepository: baseDeps.customerRepository,
            userRepository: countingUsers,
            localDirectoryCacheRefresh: baseDeps.localDirectoryCacheRefresh,
            workOrderNoteRepository: baseDeps.workOrderNoteRepository,
            workOrderPhotoRepository: baseDeps.workOrderPhotoRepository,
            workOrderLocationRepository: baseDeps.workOrderLocationRepository,
            signatureRepository: baseDeps.signatureRepository,
            statusHistoryRepository: baseDeps.statusHistoryRepository,
            editRequestRepository: baseDeps.editRequestRepository,
            editRequestService: baseDeps.editRequestService,
            customerSatisfactionRepository: baseDeps.customerSatisfactionRepository,
            customerSatisfactionService: baseDeps.customerSatisfactionService,
            notificationRepository: baseDeps.notificationRepository,
            syncOperationRepository: baseDeps.syncOperationRepository,
            syncConflictRepository: baseDeps.syncConflictRepository,
            conflictResolver: baseDeps.conflictResolver,
            networkReachability: reachability,
            profileAccountService: baseDeps.profileAccountService,
            storageDataSource: baseDeps.storageDataSource
        )

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let workOrderListCount = await countingWorkOrders.listCallCount
        let technicianListCount = await countingUsers.listCallCount
        XCTAssertEqual(workOrderListCount, 1)
        XCTAssertLessThanOrEqual(technicianListCount, 1)
        XCTAssertEqual(vm.operationsKPIs.availableTechnicians, 4)
        XCTAssertEqual(vm.operationsKPIs.availableTechnicianPreview.previewNames.count, 2)
    }

    func testDashboardUsesLocalTechnicianSnapshot() async throws {
        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser(fullName: "Cached Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await container.userRepository.save(operatorUser)
        try await container.userRepository.save(tech)
        try await container.customerRepository.save(customer)

        let reachability = FakeNetworkReachability(isReachable: false)
        let baseDeps = container.makeOperatorDependencies()
        let deps = OperatorDependencies(
            getWorkOrders: baseDeps.getWorkOrders,
            getWorkOrder: baseDeps.getWorkOrder,
            workOrderService: baseDeps.workOrderService,
            customerService: baseDeps.customerService,
            workOrderTemplateService: baseDeps.workOrderTemplateService,
            customerRepository: baseDeps.customerRepository,
            userRepository: baseDeps.userRepository,
            localDirectoryCacheRefresh: baseDeps.localDirectoryCacheRefresh,
            workOrderNoteRepository: baseDeps.workOrderNoteRepository,
            workOrderPhotoRepository: baseDeps.workOrderPhotoRepository,
            workOrderLocationRepository: baseDeps.workOrderLocationRepository,
            signatureRepository: baseDeps.signatureRepository,
            statusHistoryRepository: baseDeps.statusHistoryRepository,
            editRequestRepository: baseDeps.editRequestRepository,
            editRequestService: baseDeps.editRequestService,
            customerSatisfactionRepository: baseDeps.customerSatisfactionRepository,
            customerSatisfactionService: baseDeps.customerSatisfactionService,
            notificationRepository: baseDeps.notificationRepository,
            syncOperationRepository: baseDeps.syncOperationRepository,
            syncConflictRepository: baseDeps.syncConflictRepository,
            conflictResolver: baseDeps.conflictResolver,
            networkReachability: reachability,
            profileAccountService: baseDeps.profileAccountService,
            storageDataSource: baseDeps.storageDataSource
        )

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.operationsKPIs.availableTechnicians, 1)
        XCTAssertEqual(vm.operationsKPIs.availableTechnicianPreview.previewNames, ["Cached Tech"])
    }
}

private actor CountingListWorkOrderRepository: WorkOrderRepository {
    let inner: any WorkOrderRepository
    private(set) var listCallCount = 0

    init(inner: any WorkOrderRepository) { self.inner = inner }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        listCallCount += 1
        return try await inner.list(filter: filter)
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder { try await inner.fetch(id: id) }
    func save(_ workOrder: WorkOrder) async throws { try await inner.save(workOrder) }
    func delete(id: WorkOrderID) async throws { try await inner.delete(id: id) }
}

private actor CountingListCustomerRepository: CustomerRepository {
    let inner: any CustomerRepository
    private(set) var listCallCount = 0

    init(inner: any CustomerRepository) { self.inner = inner }

    func list(searchText: String?) async throws -> [Customer] {
        listCallCount += 1
        return try await inner.list(searchText: searchText)
    }

    func fetch(id: CustomerID) async throws -> Customer { try await inner.fetch(id: id) }
    func save(_ customer: Customer) async throws { try await inner.save(customer) }
    func delete(id: CustomerID) async throws { try await inner.delete(id: id) }
}

private actor CountingListUserRepository: UserRepository {
    let inner: any UserRepository
    private(set) var listCallCount = 0

    init(inner: any UserRepository) { self.inner = inner }

    func list(role: UserRole?, isActive: Bool?) async throws -> [User] {
        listCallCount += 1
        return try await inner.list(role: role, isActive: isActive)
    }

    func fetch(id: UserID) async throws -> User { try await inner.fetch(id: id) }
    func findByEmail(_ email: String) async throws -> User? { try await inner.findByEmail(email) }
    func save(_ user: User) async throws { try await inner.save(user) }
    func updateSelfServiceProfile(_ user: User) async throws { try await inner.updateSelfServiceProfile(user) }
    func delete(id: UserID) async throws { try await inner.delete(id: id) }
}
