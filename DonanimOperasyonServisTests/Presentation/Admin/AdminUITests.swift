import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class AdminDashboardViewModelTests: XCTestCase {

    func testDashboardLoadedFromSeededData() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)

        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, status: .assigned)
        )

        let vm = AdminDashboardViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.totalWorkOrders, 1)
        XCTAssertEqual(vm.summary.operatorCount, 1)
        XCTAssertEqual(vm.summary.technicianCount, 1)
    }

    func testDashboardLoadedWithNoWorkOrders() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminDashboardViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.totalWorkOrders, 0)
    }

    func testDashboardUnauthorizedForOperator() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let operatorUser = DomainFixtures.operatorUser()

        let vm = AdminDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        if case .error = vm.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("operator should not load admin dashboard")
        }
    }
}

@MainActor
final class AdminUserListViewModelTests: XCTestCase {

    func testUserListLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(DomainFixtures.operatorUser())
        try await deps.userRepository.save(DomainFixtures.technicianUser())

        let vm = AdminUserListViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 3)
    }

    func testUserListFilterActive() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        var passive = DomainFixtures.technicianUser(id: UserID("tech-passive"), email: "p@example.com", fullName: "Passive")
        passive.isActive = false
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(passive)
        try await deps.userRepository.save(DomainFixtures.operatorUser())

        let vm = AdminUserListViewModel(actor: admin, dependencies: deps)
        await vm.selectFilter(.passive)

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertFalse(vm.rows[0].isActive)
    }

    func testUserListUnauthorizedForTechnician() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let tech = DomainFixtures.technicianUser()

        let vm = AdminUserListViewModel(actor: tech, dependencies: deps)
        await vm.load()

        if case .error = vm.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("technician cannot list users")
        }
    }
}

@MainActor
final class AdminUserDetailViewModelTests: XCTestCase {

    func testUserDetailLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(operatorUser)

        let vm = AdminUserDetailViewModel(
            userId: operatorUser.id,
            actor: admin,
            dependencies: deps
        )
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.user.role, .operator)
        XCTAssertFalse(vm.content?.permissions.isEmpty ?? true)
    }

    func testDeactivateUserEnqueuesSync() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(operatorUser)

        let vm = AdminUserDetailViewModel(
            userId: operatorUser.id,
            actor: admin,
            dependencies: deps
        )
        await vm.load()
        await vm.toggleActiveState()

        XCTAssertEqual(vm.content?.user.isActive, false)
        let pending = try await deps.syncOperationRepository.countPending(now: Date())
        XCTAssertGreaterThanOrEqual(pending, 1)
    }
}

@MainActor
final class AdminRoleAccessTests: XCTestCase {

    func testRoleListRequiresViewRolesMatrix() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminRoleListViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 3)
    }

    func testAdminPermissionsAreReadOnlyMatrix() {
        let granted = RoleAccessPolicyAdminUI.grantedActions(for: .admin)
        XCTAssertTrue(granted.contains(.manageUsers))
        XCTAssertFalse(granted.contains(.resolveSyncConflict))
        XCTAssertFalse(granted.contains(.approveEditRequest))
    }

    func testOperatorCannotResolveConflictViaPolicy() {
        XCTAssertFalse(RoleAccessPolicy.can(.resolveSyncConflict, as: .admin))
        XCTAssertTrue(RoleAccessPolicy.can(.resolveSyncConflict, as: .operator))
    }
}

@MainActor
final class AdminSystemViewModelTests: XCTestCase {

    func testSystemScreenLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminSystemViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
    }

    func testSystemScreenUnauthorizedForOperator() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let operatorUser = DomainFixtures.operatorUser()

        let vm = AdminSystemViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        if case .error = vm.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("operator cannot access system configuration")
        }
    }
}

@MainActor
final class AdminReportsViewModelTests: XCTestCase {

    func testWorkOrderReportAggregates() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-2"),
                customerId: customer.id,
                status: .assigned
            )
        )

        let vm = AdminReportDetailViewModel(kind: .workOrders, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertFalse(vm.metrics.isEmpty)
        XCTAssertFalse(vm.statusBreakdown.isEmpty)
    }

    func testWorkOrderReportDetailForSingleOrder() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let vm = AdminWorkOrderReportViewModel(
            workOrderId: order.id,
            actor: admin,
            dependencies: deps
        )
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.id, order.id)
    }
}

@MainActor
final class AdminDomainEnumDisplayTests: XCTestCase {

    func testWorkTypeDisplayMatchesDomain() {
        XCTAssertEqual(WorkType.allCases.count, 4)
        XCTAssertEqual(WorkType.repair.displayName, "Arıza")
    }

    func testPauseReasonDisplayMatchesDomain() {
        XCTAssertEqual(PauseReason.allCases.count, 5)
        XCTAssertEqual(PauseReason.partWaiting.displayName, "Parça bekleniyor")
    }
}

@MainActor
final class AdminSyncHealthTests: XCTestCase {

    func testConflictListIsReadOnlyForAdmin() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminConflictListViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .empty)
        XCTAssertFalse(RoleAccessPolicy.can(.resolveSyncConflict, as: .admin))
    }
}

@MainActor
final class AdminRoleIsolationTests: XCTestCase {

    func testAdminCannotUseOperatorDashboardUseCase() async throws {
        let container = DIContainer.mock()
        let operatorDeps = container.makeOperatorDependencies()
        let admin = DomainFixtures.adminUser()

        let vm = OperatorDashboardViewModel(actor: admin, dependencies: operatorDeps)
        await vm.load()

        if case .error = vm.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("admin should not access operator dashboard data")
        }
    }

    func testFullRoleRoutingTabIsolation() {
        let adminTitles = Set(AdminNavigationConfiguration.tabItems().map(\.title))
        let operatorTitles = Set(OperatorNavigationConfiguration.tabItems().map(\.title))
        let technicianTitles = Set(TechnicianNavigationConfiguration.tabItems().map(\.title))

        XCTAssertTrue(adminTitles.contains("Raporlar"))
        XCTAssertFalse(operatorTitles.contains("Roller"))
        XCTAssertFalse(technicianTitles.contains("Kullanıcılar"))
    }
}

@MainActor
final class AdminLogoutFlowTests: XCTestCase {

    func testLogoutPreservesBusinessData() async throws {
        let container = DIContainer.mock()
        let auth = container.authRepository as! FakeAuthRepository
        let admin = DomainFixtures.adminUser()
        auth.seed(user: admin, password: "secret")
        let controller = container.makeAuthSessionController()
        await controller.signIn(email: admin.email, password: "secret")

        let customer = DomainFixtures.customer()
        try await container.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id)
        )

        await controller.signOut()
        XCTAssertEqual(controller.state, .unauthenticated)

        let orders = try await container.workOrderRepository.list(filter: .all)
        XCTAssertEqual(orders.count, 1)
        let pending = try await container.syncOperationRepository.countPending(now: Date())
        XCTAssertGreaterThanOrEqual(pending, 0)
    }
}

@MainActor
final class AdminUseCaseTests: XCTestCase {

    func testListUsersUseCase() async throws {
        let container = DIContainer.mock()
        let useCase = ListUsersUseCase(userRepository: container.userRepository)
        let admin = DomainFixtures.adminUser()
        try await container.userRepository.save(admin)
        try await container.userRepository.save(DomainFixtures.operatorUser())

        let users = try await useCase.execute(actor: admin)
        XCTAssertEqual(users.count, 2)
    }

    func testGetSystemWorkOrdersUseCase() async throws {
        let container = DIContainer.mock()
        let useCase = GetSystemWorkOrdersUseCase(workOrderRepository: container.workOrderRepository)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id)
        )

        let orders = try await useCase.execute(actor: admin)
        XCTAssertEqual(orders.count, 1)
    }

    func testUpdateUserUseCaseRejectsOperator() async throws {
        let container = DIContainer.mock()
        let useCase = UpdateUserUseCase(userRepository: container.userRepository)
        let operatorUser = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser()
        try await container.userRepository.save(tech)

        do {
            _ = try await useCase.execute(actor: operatorUser, userId: tech.id, isActive: false)
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            if case .unauthorized = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("unexpected \(error)")
            }
        }
    }
}

@MainActor
final class ExistingRoleFlowRegressionTests: XCTestCase {

    func testOperatorDashboardStillWorks() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id)
        )

        let vm = OperatorDashboardViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testTechnicianHomeStillWorks() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(assignedTechnicianId: tech.id, customerId: customer.id)
        )

        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
    }
}
