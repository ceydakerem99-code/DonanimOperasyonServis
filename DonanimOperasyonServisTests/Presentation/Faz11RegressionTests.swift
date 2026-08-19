import XCTest
@testable import DonanimOperasyonServis

/// Faz 11 regression coverage for end-to-end operator/technician usability.
@MainActor
final class Faz11CustomerFlowTests: XCTestCase {

    func testCreateCustomerPersistsAndEnqueuesSync() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let created = try await deps.customerService.createWithSync(
            actor: operatorUser,
            name: "Yeni Firma",
            contactPersonName: "Ali",
            phoneNumber: PhoneNumber("+905551234567"),
            email: "yeni@example.com",
            address: "Demo Cad. No:1",
            city: "Ankara",
            notes: "Faz11"
        )

        let stored = try await deps.customerRepository.fetch(id: created.id)
        XCTAssertEqual(stored.name, "Yeni Firma")

        let ops = try await deps.syncOperationRepository.list(
            entityType: .customer,
            entityId: created.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create && $0.status == .pending })
    }

    func testCreateCustomerUseCaseRejectsEmptyName() async {
        let container = DIContainer.mock()
        let useCase = CreateCustomerUseCase(customerRepository: container.customerRepository)
        do {
            _ = try await useCase.execute(
                actor: DomainFixtures.operatorUser(),
                name: "   ",
                address: "Adres"
            )
            XCTFail("expected invalidData")
        } catch let error as DomainError {
            if case .invalidData(let reason) = error {
                XCTAssertEqual(reason, "customer.nameEmpty")
            } else {
                XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testWizardCreatesCustomerAndAutoSelects() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.openCreateCustomer()
        vm.newCustomerName = "Wizard Müşteri"
        vm.newCustomerAddress = "Cadde 10"
        vm.newCustomerCity = "Çorum"
        await vm.createCustomer()

        XCTAssertFalse(vm.showsCreateCustomer)
        XCTAssertEqual(vm.draft.customer?.name, "Wizard Müşteri")
        XCTAssertEqual(vm.customers.first?.name, "Wizard Müşteri")
        XCTAssertNil(vm.newCustomerError)
    }

    func testWizardEmptyCustomerListStillAllowsCreateAction() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        await vm.loadSelections()

        XCTAssertTrue(vm.customers.isEmpty)
        vm.openCreateCustomer()
        XCTAssertTrue(vm.showsCreateCustomer)
    }

    func testCustomerSearchFiltersResults() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)
        try await deps.customerRepository.save(
            DomainFixtures.customer(id: CustomerID("c1"), name: "ABC Market", createdByUserId: operatorUser.id)
        )
        try await deps.customerRepository.save(
            DomainFixtures.customer(id: CustomerID("c2"), name: "XYZ Mağaza", createdByUserId: operatorUser.id)
        )

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        await vm.updateCustomerSearch("ABC")
        XCTAssertEqual(vm.customers.map(\.name), ["ABC Market"])
    }
}

@MainActor
final class Faz11ListLifecycleTests: XCTestCase {

    func testWorkOrderListEmptyLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .empty)
        XCTAssertTrue(vm.cards.isEmpty)
    }

    func testWorkOrderListLoadedLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(DomainFixtures.workOrder(customerId: customer.id))

        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.cards.count, 1)
    }

    func testWorkOrderListErrorLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let admin = DomainFixtures.adminUser()

        let vm = OperatorWorkOrderListViewModel(actor: admin, dependencies: deps)
        await vm.load()
        if case .error = vm.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("expected error phase, got \(vm.phase)")
        }
    }

    func testNotificationEmptyLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .empty)
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

    func testTechnicianWorkOrderListEmptyLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()

        let vm = TechnicianWorkOrderListViewModel(actor: tech, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .empty)
    }

    func testTechnicianNotificationEmptyLeavesLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()

        let vm = TechnicianNotificationListViewModel(actor: tech, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .empty)
    }
}

@MainActor
final class Faz11WizardNavigationTests: XCTestCase {

    func testCompleteWizardFlowCreatesWorkOrderVisibleInList() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()

        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let wizard = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        wizard.selectWorkType(.repair)
        wizard.nextStep()
        XCTAssertEqual(wizard.currentStep, 2)

        wizard.selectCustomer(customer)
        wizard.nextStep()
        XCTAssertEqual(wizard.currentStep, 3)

        wizard.draft.deviceBrand = "Ingenico"
        wizard.draft.deviceModel = "iCT250"
        wizard.draft.serialNumber = "SN-FAZ11"
        wizard.nextStep()
        XCTAssertEqual(wizard.currentStep, 4)

        wizard.nextStep()
        XCTAssertEqual(wizard.currentStep, 5)

        wizard.selectTechnician(technician)
        wizard.nextStep()
        XCTAssertEqual(wizard.currentStep, 6)

        await wizard.submit()
        guard case .success(let id) = wizard.phase else {
            return XCTFail("expected success, got \(wizard.phase)")
        }

        let list = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await list.load()
        XCTAssertEqual(list.phase, .loaded)
        XCTAssertTrue(list.cards.contains { $0.id == id.rawValue })

        let detail = OperatorWorkOrderDetailViewModel(
            workOrderId: id,
            actor: operatorUser,
            dependencies: deps
        )
        await detail.load()
        XCTAssertEqual(detail.phase, .loaded)

        let history = try await deps.statusHistoryRepository.list(for: id)
        XCTAssertFalse(history.isEmpty)
    }

    func testWizardPushHidesTabBarPathNonEmpty() {
        let router = OperatorAppRouter(selectedTab: .profile)
        XCTAssertTrue(router.path.isEmpty)
        router.push(.newWorkOrderWizard)
        XCTAssertFalse(router.path.isEmpty)
        XCTAssertEqual(router.path.last, .newWorkOrderWizard)
        // Tab bar visibility is driven by `path.isEmpty` in AppShellLayout.
    }

    func testDemoAccountsSeedOnlyWhenMissing() async throws {
        let container = DIContainer.mock()
        await DemoAccountSeeder.seedIfNeeded(container: container)

        let marker = try await container.customerRepository.fetch(id: CustomerID("demo-cust-abc"))
        XCTAssertEqual(marker.id, CustomerID("demo-cust-abc"))

        let firstCount = try await container.workOrderRepository.list(filter: WorkOrderFilter()).count
        await DemoAccountSeeder.seedIfNeeded(container: container)
        let secondCount = try await container.workOrderRepository.list(filter: WorkOrderFilter()).count
        XCTAssertEqual(firstCount, secondCount)
        XCTAssertGreaterThanOrEqual(firstCount, 7)
    }
}

@MainActor
final class Faz11TechnicianMapAndAccessTests: XCTestCase {

    func testTechnicianCannotAccessOtherTechnicianWorkOrder() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"))
        let techB = DomainFixtures.technicianUser(id: UserID("tech-b"), email: "b@example.com", fullName: "Tech B")
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techB.id,
            customerId: customer.id,
            status: .assigned
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        do {
            _ = try await deps.getWorkOrder.execute(actor: techA, id: order.id)
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            if case .unauthorized = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("unexpected \(error)")
            }
        }
    }

    func testTechnicianSeesAssignedWorkOrder() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .assigned
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let orders = try await deps.getWorkOrders.execute(actor: tech)
        XCTAssertEqual(orders.map(\.id), [order.id])
    }

    func testMapSectionBuildsWithAddressAndLocations() {
        let location = WorkOrderLocation(
            id: "loc-1",
            workOrderId: WorkOrderID("wo-1"),
            event: .arrived,
            coordinate: LocationCoordinate(latitude: 39.9, longitude: 32.8),
            capturedByUserId: UserID("tech-1"),
            capturedAt: DomainFixtures.referenceDate
        )
        let section = WorkOrderMapSection(
            customerName: "ABC",
            address: "Demo Cad.",
            city: "Ankara",
            capturedLocations: [location]
        )
        XCTAssertEqual(section.customerName, "ABC")
        XCTAssertEqual(section.capturedLocations.count, 1)
    }
}

@MainActor
final class Faz11LogoutRegressionTests: XCTestCase {

    func testLogoutReturnsUnauthenticatedWithoutWipingBusinessData() async throws {
        let harness = try SwiftDataTestHarness()
        let auth = FakeAuthRepository(store: harness.store, localUsers: harness.users)
        let controller = AuthSessionController(authRepository: auth)
        let user = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: user.id)
        try await harness.users.save(user)
        try await harness.customers.save(customer)
        auth.seed(user: user, password: "DopsTest123!")

        await controller.signIn(email: user.email, password: "DopsTest123!")
        guard case .authenticated = controller.state else {
            return XCTFail("expected authenticated")
        }

        await controller.signOut()
        XCTAssertEqual(controller.state, .unauthenticated)
        let stored = try await harness.customers.fetch(id: customer.id)
        XCTAssertEqual(stored, customer)
    }
}
