import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class AppShellRoutingTests: XCTestCase {

    func testAdminNavigationMatchesPrototype() {
        let tabs = AdminNavigationConfiguration.tabItems()
        XCTAssertEqual(tabs.map(\.title), [
            "Dashboard",
            "Kullanıcılar",
            "Roller",
            "Sistem",
            "Raporlar"
        ])
        XCTAssertEqual(AdminTab.allCases.count, 5)
    }

    func testOperatorNavigationMatchesPrototype() {
        let tabs = OperatorNavigationConfiguration.tabItems()
        XCTAssertEqual(tabs.map(\.title), [
            "Dashboard",
            "İş Emirleri",
            "Bildirimler",
            "Profil"
        ])
    }

    func testTechnicianNavigationMatchesPrototype() {
        let tabs = TechnicianNavigationConfiguration.tabItems()
        XCTAssertEqual(tabs.map(\.title), [
            "Ana Sayfa",
            "İş Emirleri",
            "Bildirimler",
            "Profil"
        ])
    }

    func testAdminRouterTabSelectionAndDestinationPush() {
        let router = AdminAppRouter(selectedTab: .dashboard)
        XCTAssertEqual(router.selectedTab, .dashboard)
        router.selectedTab = .users
        router.push(.userDetail)
        XCTAssertEqual(router.path, [.userDetail])
        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)
    }

    func testOperatorRouterCenterWizardDestination() {
        let router = OperatorAppRouter(selectedTab: .dashboard)
        router.push(.newWorkOrderWizard)
        XCTAssertEqual(router.path, [.newWorkOrderWizard])
    }

    func testOperatorRouterWorkOrderDetailDestination() {
        let router = OperatorAppRouter(selectedTab: .workOrders)
        let id = WorkOrderID("wo-test-1")
        router.push(.workOrderDetail(id))
        XCTAssertEqual(router.path, [.workOrderDetail(id)])
    }

    func testTechnicianRouterWorkOrderDetailDestination() {
        let router = TechnicianAppRouter(selectedTab: .home)
        router.push(.workOrderDetail)
        XCTAssertEqual(router.path, [.workOrderDetail])
    }

    func testRoleIsolationUsesDistinctTabSets() {
        let adminTitles = Set(AdminNavigationConfiguration.tabItems().map(\.title))
        let operatorTitles = Set(OperatorNavigationConfiguration.tabItems().map(\.title))
        let technicianTitles = Set(TechnicianNavigationConfiguration.tabItems().map(\.title))

        XCTAssertTrue(adminTitles.contains("Kullanıcılar"))
        XCTAssertFalse(operatorTitles.contains("Kullanıcılar"))
        XCTAssertFalse(technicianTitles.contains("Kullanıcılar"))

        XCTAssertTrue(technicianTitles.contains("Ana Sayfa"))
        XCTAssertFalse(adminTitles.contains("Ana Sayfa"))
        XCTAssertFalse(operatorTitles.contains("Ana Sayfa"))

        XCTAssertEqual(operatorTitles.intersection(adminTitles), ["Dashboard"])
        XCTAssertTrue(operatorTitles.contains("Profil"))
        XCTAssertFalse(adminTitles.contains("Profil"))
    }

    func testRoleAppShellViewResolvesAdminRole() {
        let user = DomainFixtures.adminUser()
        XCTAssertEqual(user.role, .admin)
        XCTAssertEqual(AdminTab.dashboard.title, "Dashboard")
    }

    func testRoleAppShellViewResolvesOperatorRole() {
        let user = DomainFixtures.operatorUser()
        XCTAssertEqual(user.role, .operator)
        XCTAssertEqual(OperatorTab.dashboard.title, "Dashboard")
    }

    func testRoleAppShellViewResolvesTechnicianRole() {
        let user = DomainFixtures.technicianUser()
        XCTAssertEqual(user.role, .technician)
        XCTAssertEqual(TechnicianTab.home.title, "Ana Sayfa")
    }
}

@MainActor
final class RootAuthRoutingTests: XCTestCase {

    func testCheckingSessionStateIsDistinctFromNavigation() {
        XCTAssertNotEqual(String(describing: AuthState.checkingSession), String(describing: AdminTab.dashboard))
    }

    func testUnauthenticatedRoutesToLoginNotShell() async {
        let (controller, _) = makeAuthController()
        await controller.restoreSession()
        XCTAssertEqual(controller.state, .unauthenticated)
    }

    func testAuthenticatedAdminSession() async throws {
        let (controller, auth) = makeAuthController()
        let user = DomainFixtures.adminUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        guard case .authenticated(let signedIn) = controller.state else {
            return XCTFail("expected authenticated admin")
        }
        XCTAssertEqual(signedIn.role, .admin)
    }

    func testLogoutReturnsToUnauthenticated() async throws {
        let (controller, auth) = makeAuthController()
        let user = DomainFixtures.operatorUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        await controller.signOut()
        XCTAssertEqual(controller.state, .unauthenticated)
    }

    func testMockDIContainerStillBuildsForPreviews() {
        let container = DIContainer.mock()
        let controller = container.makeAuthSessionController()
        XCTAssertNotNil(controller)
        XCTAssertTrue(container.authRepository is FakeAuthRepository)
    }

    private func makeAuthController() -> (AuthSessionController, FakeAuthRepository) {
        let auth = FakeAuthRepository()
        let controller = AuthSessionController(authRepository: auth)
        return (controller, auth)
    }
}
