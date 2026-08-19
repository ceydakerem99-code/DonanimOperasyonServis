import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class Faz12AUserManagementTests: XCTestCase {

    func testUserDetailNavigationContentLoads() async throws {
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
        XCTAssertEqual(vm.content?.user.email, operatorUser.email)
        XCTAssertEqual(vm.passwordResetUnsupportedMessage, AdminUnsupportedAction.message)
    }

    func testAssignRoleUpdatesUserAndEnqueuesSync() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let tech = DomainFixtures.technicianUser()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(tech)

        let vm = AdminUserDetailViewModel(userId: tech.id, actor: admin, dependencies: deps)
        await vm.load()
        vm.requestRoleChange(.operator)
        await vm.confirmRoleChange()

        XCTAssertEqual(vm.content?.user.role, .operator)
        let ops = try await deps.syncOperationRepository.list(
            entityType: .user,
            entityId: tech.id.rawValue
        )
        XCTAssertFalse(ops.isEmpty)
    }

    func testCannotChangeOwnRoleOrActiveState() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminUserDetailViewModel(userId: admin.id, actor: admin, dependencies: deps)
        await vm.load()
        XCTAssertTrue(vm.isViewingSelf)

        vm.requestRoleChange(.operator)
        XCTAssertFalse(vm.showsRoleConfirmation)
        XCTAssertEqual(vm.actionMessage, "Kendi rolünüzü değiştiremezsiniz.")

        vm.requestToggleActive()
        XCTAssertFalse(vm.showsActiveConfirmation)
        XCTAssertEqual(vm.actionMessage, "Kendi hesabınızın durumunu değiştiremezsiniz.")
    }

    func testUserListRoleFilterTechnicians() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(DomainFixtures.operatorUser())
        try await deps.userRepository.save(DomainFixtures.technicianUser())

        let vm = AdminUserListViewModel(actor: admin, dependencies: deps)
        await vm.applyRoleFilter(.technician)

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].roleLabel, UserRole.technician.displayName)
    }

    func testUserListEmptyState() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminUserListViewModel(actor: admin, dependencies: deps)
        await vm.applyRoleFilter(.technician)
        // Only admin exists — technician filter empty
        XCTAssertEqual(vm.phase, .empty)
    }
}

@MainActor
final class Faz12AReportsAndNavigationTests: XCTestCase {

    func testTechnicianReportUsesDisplayNames() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let tech = DomainFixtures.technicianUser(fullName: "Ahmet Yılmaz")
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                status: .assigned
            )
        )

        let vm = AdminReportDetailViewModel(kind: .technicianPerformance, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.metrics.contains { $0.title == "Ahmet Yılmaz" })
        XCTAssertFalse(vm.statusBreakdown.isEmpty)
    }

    func testCustomerReportUsesCustomerNames() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer(name: "ABC Market")
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id)
        )

        let vm = AdminReportDetailViewModel(kind: .customerSummary, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.metrics.first?.title, "ABC Market")
    }

    func testSignatureReportCountsAndRelatedNavigationIds() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        try await deps.signatureRepository.save(
            DomainFixtures.signature(workOrderId: order.id, kind: .customer)
        )

        let vm = AdminReportDetailViewModel(kind: .signatures, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.metrics.contains { $0.title == "Toplam İmza" && $0.value == "1" })
        XCTAssertEqual(vm.relatedWorkOrders.first?.id, order.id)
    }

    func testWorkOrderReportIncludesSignatureAndPhotoCounts() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        try await deps.signatureRepository.save(
            DomainFixtures.signature(workOrderId: order.id, kind: .customer)
        )
        try await deps.workOrderPhotoRepository.save(
            DomainFixtures.photo(workOrderId: order.id, category: .before)
        )

        let vm = AdminWorkOrderReportViewModel(
            workOrderId: order.id,
            actor: admin,
            dependencies: deps
        )
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.signatureCount, 1)
        XCTAssertEqual(vm.content?.photoCount, 1)
    }

    func testAdminDestinationUserDetailAndReportNavigation() {
        let router = AdminAppRouter(selectedTab: .dashboard)
        let userId = UserID("u-1")
        router.push(.userDetail(userId))
        XCTAssertEqual(router.path.last, .userDetail(userId))
        router.popToRoot()
        router.selectedTab = .reports
        router.push(.reportDetail(.signatures))
        XCTAssertEqual(router.path.last, .reportDetail(.signatures))
        router.push(.workOrderReport(WorkOrderID("wo-1")))
        XCTAssertEqual(router.path.last, .workOrderReport(WorkOrderID("wo-1")))
    }

    func testAdminUnauthorizedCannotListUsers() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let operatorUser = DomainFixtures.operatorUser()

        let vm = AdminUserListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        if case .error = vm.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("operator must not list admin users")
        }
    }
}

@MainActor
final class Faz12AProfileLogoutTests: XCTestCase {

    func testUnsupportedActionCopy() {
        XCTAssertEqual(AdminUnsupportedAction.message, "Bu işlem bu sürümde desteklenmiyor.")
    }

    func testAdminLogoutPreservesBusinessData() async throws {
        let harness = try SwiftDataTestHarness()
        let auth = FakeAuthRepository(store: harness.store, localUsers: harness.users)
        let controller = AuthSessionController(authRepository: auth)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer(createdByUserId: admin.id)
        try await harness.users.save(admin)
        try await harness.customers.save(customer)
        auth.seed(user: admin, password: "DopsTest123!")

        await controller.signIn(email: admin.email, password: "DopsTest123!")
        await controller.signOut()

        XCTAssertEqual(controller.state, .unauthenticated)
        let stored = try await harness.customers.fetch(id: customer.id)
        XCTAssertEqual(stored, customer)
    }
}
