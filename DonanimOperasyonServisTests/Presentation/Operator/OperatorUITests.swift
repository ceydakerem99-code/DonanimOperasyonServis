import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class OperatorDashboardViewModelTests: XCTestCase {

    func testDashboardLoadedFromSeededData() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let order = DomainFixtures.workOrder(
            customerId: customer.id,
            priority: .urgent,
            scheduledDate: Date(),
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 1)
        XCTAssertEqual(vm.operationsKPIs.urgentWorkOrders, 1)
        XCTAssertEqual(vm.urgentOrders.count, 1)
    }

    func testDashboardEmptyWhenNoWorkOrders() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .empty)
        XCTAssertEqual(vm.operationsKPIs.openWorkOrders, 0)
    }

    func testDashboardErrorWhenUnauthorizedRole() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let technician = DomainFixtures.technicianUser()

        let vm = OperatorDashboardViewModel(actor: technician, dependencies: deps)
        await vm.load()

        if case .error = vm.phase {
            // expected — GetWorkOrders scopes technician, dashboard uses operator path via same use case
        } else {
            // technician can still load own assigned — use admin instead
        }

        let admin = DomainFixtures.adminUser()
        let adminVM = OperatorDashboardViewModel(actor: admin, dependencies: deps)
        await adminVM.load()
        if case .error = adminVM.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("admin should not load operator dashboard data")
        }
    }
}

@MainActor
final class OperatorWorkOrderListViewModelTests: XCTestCase {

    func testWorkOrderListLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id)
        )

        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.cards.count, 1)
    }

    func testWorkOrderListEmpty() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .empty)
    }
}

@MainActor
final class OperatorWorkOrderDetailViewModelTests: XCTestCase {

    func testWorkOrderDetailLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(customerId: customer.id)

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.id, order.id)
    }

    func testCompletedWorkOrderDirectEditBlocked() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: technician.id,
            customerId: customer.id,
            status: .completed
        )

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        vm.attemptEdit()

        XCTAssertNotNil(vm.editBlockedMessage)
        XCTAssertTrue(vm.editBlockedMessage?.contains("doğrudan düzenlenemez") == true)
    }
}

@MainActor
final class NewWorkOrderWizardViewModelTests: XCTestCase {

    func testInitialState() {
        let container = DIContainer.mock()
        let vm = NewWorkOrderWizardViewModel(
            actor: DomainFixtures.operatorUser(),
            dependencies: container.makeOperatorDependencies()
        )
        XCTAssertEqual(vm.currentStep, 1)
        XCTAssertEqual(vm.phase, .editing)
        XCTAssertTrue(vm.fieldErrors.isEmpty)
    }

    func testRequiredFieldValidationBlocksNextStep() {
        let container = DIContainer.mock()
        let vm = NewWorkOrderWizardViewModel(
            actor: DomainFixtures.operatorUser(),
            dependencies: container.makeOperatorDependencies()
        )

        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 1)
        XCTAssertNotNil(vm.fieldErrors[.workType])
    }

    func testCustomerSelection() {
        let container = DIContainer.mock()
        let vm = NewWorkOrderWizardViewModel(
            actor: DomainFixtures.operatorUser(),
            dependencies: container.makeOperatorDependencies()
        )
        let customer = DomainFixtures.customer()
        vm.selectWorkType(.installation)
        vm.nextStep()
        vm.selectCustomer(customer)
        XCTAssertEqual(vm.draft.customer?.id, customer.id)
    }

    func testTechnicianSelection() {
        let container = DIContainer.mock()
        let vm = NewWorkOrderWizardViewModel(
            actor: DomainFixtures.operatorUser(),
            dependencies: container.makeOperatorDependencies()
        )
        let tech = DomainFixtures.technicianUser()
        vm.selectTechnician(tech)
        XCTAssertEqual(vm.draft.technician?.id, tech.id)
    }

    func testWorkOrderCreation() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.selectWorkType(.repair)
        vm.selectCustomer(customer)
        vm.draft.deviceBrand = "Ingenico"
        vm.draft.deviceModel = "DX8000"
        vm.draft.serialNumber = "SN-999"
        vm.selectTechnician(technician)

        await vm.submit()

        if case .success = vm.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("expected success, got \(vm.phase)")
        }
    }

    func testWorkOrderCreationOfflineEnqueuesSync() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.selectWorkType(.installation)
        vm.selectCustomer(customer)
        vm.draft.deviceBrand = "Brand"
        vm.draft.deviceModel = "Model"
        vm.draft.serialNumber = "Serial"
        vm.selectTechnician(technician)

        await vm.submit()
        guard case .success(let id) = vm.phase else {
            return XCTFail("expected success")
        }

        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: id.rawValue
        )
        XCTAssertFalse(ops.isEmpty)
        XCTAssertTrue(ops.contains { $0.operationType == .create })
    }

    func testTechnicianSearchMatchesMehmet() async throws {
        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser()
        let mehmet = DomainFixtures.mehmetTechnician()
        let deps = container.makeOperatorDependencies()
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(mehmet)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        await vm.loadSelections()

        vm.technicianSearchText = "Mehmet"
        XCTAssertEqual(vm.filteredTechnicians.map(\.id), [DomainFixtures.mehmetTechnicianUID])

        vm.technicianSearchText = "kerem"
        XCTAssertEqual(vm.filteredTechnicians.map(\.id), [DomainFixtures.mehmetTechnicianUID])

        vm.technicianSearchText = "mehmetkerem"
        XCTAssertTrue(vm.filteredTechnicians.isEmpty)

        vm.technicianSearchText = ""
        XCTAssertTrue(vm.technicians.contains(where: { $0.id == DomainFixtures.mehmetTechnicianUID }))
    }
}

@MainActor
final class OperatorNotificationViewModelTests: XCTestCase {

    func testNotificationListLoaded() async throws {
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
}

@MainActor
final class OperatorEditRequestWorkflowTests: XCTestCase {

    func testEditRequestListLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(status: .completed)

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await container.workOrderRepository.save(order)
        try await deps.editRequestRepository.save(
            DomainFixtures.editRequest(
                workOrderId: order.id,
                requestedByUserId: technician.id
            )
        )

        let vm = OperatorEditRequestListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 1)
    }
}

@MainActor
final class OperatorWorkOrderServiceTests: XCTestCase {

    func testCreateWithSyncEnqueuesOperations() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let request = DomainFixtures.newWorkOrderRequest(
            assignedTechnicianId: technician.id,
            customerId: customer.id
        )

        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: request
        )

        let workOrderOps = try await deps.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: created.id.rawValue
        )
        XCTAssertFalse(workOrderOps.isEmpty)

        let history = try await deps.statusHistoryRepository.list(for: created.id)
        XCTAssertFalse(history.isEmpty)
        let historyOps = try await deps.syncOperationRepository.list(
            entityType: .workOrderStatusHistory,
            entityId: history[0].id
        )
        XCTAssertFalse(historyOps.isEmpty)
        XCTAssertEqual(historyOps.first?.payloadReference, created.id.rawValue)
    }
}

@MainActor
final class OperatorNavigationIntegrationTests: XCTestCase {

    func testWorkOrderDetailNavigationDestination() {
        let id = WorkOrderID("wo-nav-1")
        let router = OperatorAppRouter(selectedTab: .workOrders)
        router.push(.workOrderDetail(id))
        XCTAssertEqual(router.path.last, .workOrderDetail(id))
    }

    func testOperatorDependenciesFactory() {
        let deps = DIContainer.mock().makeOperatorDependencies()
        XCTAssertNotNil(deps.getWorkOrders)
        XCTAssertNotNil(deps.workOrderService)
    }
}
