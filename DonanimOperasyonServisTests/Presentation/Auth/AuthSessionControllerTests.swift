import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class AuthSessionControllerTests: XCTestCase {

    private func makeController(
        store: LocalPersistence? = nil,
        users: (any UserRepository)? = nil
    ) -> (AuthSessionController, FakeAuthRepository) {
        let auth = FakeAuthRepository(store: store, localUsers: users)
        let controller = AuthSessionController(authRepository: auth)
        return (controller, auth)
    }

    func testInitialSessionCheckingThenUnauthenticated() async {
        let (controller, _) = makeController()
        XCTAssertEqual(controller.state, .checkingSession)
        await controller.start()
        XCTAssertEqual(controller.state, .unauthenticated)
    }

    func testNoSessionRestoresToUnauthenticated() async {
        let (controller, _) = makeController()
        await controller.restoreSession()
        XCTAssertEqual(controller.state, .unauthenticated)
    }

    func testValidSessionRestoresToAuthenticated() async throws {
        let harness = try SwiftDataTestHarness()
        let (controller, auth) = makeController(store: harness.store, users: harness.users)
        let user = DomainFixtures.adminUser()
        auth.seed(user: user, password: "secret")
        try await auth.simulateExternalSignIn(user: user)

        await controller.restoreSession()
        guard case .authenticated(let restored) = controller.state else {
            return XCTFail("expected authenticated, got \(controller.state)")
        }
        XCTAssertEqual(restored, user)
    }

    func testLoginSuccess() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.operatorUser(email: "op@test.com")
        auth.seed(user: user, password: "pass123")

        await controller.signIn(email: "op@test.com", password: "pass123")
        guard case .authenticated(let signedIn) = controller.state else {
            return XCTFail("expected authenticated")
        }
        XCTAssertEqual(signedIn.role, .operator)
    }

    func testInvalidCredentials() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.adminUser(email: "admin@test.com")
        auth.seed(user: user, password: "right")

        await controller.signIn(email: "admin@test.com", password: "wrong")
        guard case .authenticationError(.authenticationFailed(.invalidCredentials)) = controller.state else {
            return XCTFail("expected invalid credentials")
        }
    }

    func testNetworkAuthFailure() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.adminUser()
        auth.seed(user: user, password: "secret")
        auth.setNetworkFailure(true)

        await controller.signIn(email: user.email, password: "secret")
        guard case .authenticationError(.authenticationFailed(.networkUnavailable)) = controller.state else {
            return XCTFail("expected network failure")
        }
    }

    func testFirebaseUserExistsButFirestoreUserMissing() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.technicianUser(email: "tech@test.com")
        auth.seed(user: user, password: "secret")
        auth.setMissingProfile(uid: user.id.rawValue)

        await controller.signIn(email: user.email, password: "secret")
        guard case .authenticationError(.authenticationFailed(.userDocumentMissing)) = controller.state else {
            return XCTFail("expected missing profile")
        }
    }

    func testLogoutBecomesUnauthenticated() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.adminUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        await controller.signOut()
        XCTAssertEqual(controller.state, .unauthenticated)
    }

    func testLogoutPreservesLocalBusinessData() async throws {
        let harness = try SwiftDataTestHarness()
        let (controller, auth) = makeController(store: harness.store, users: harness.users)
        let user = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await harness.users.save(user)
        try await harness.customers.save(customer)
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        await controller.signOut()

        let storedCustomer = try await harness.customers.fetch(id: customer.id)
        XCTAssertEqual(storedCustomer, customer)
    }

    func testLogoutPreservesSyncQueue() async throws {
        let harness = try SwiftDataTestHarness()
        let (controller, auth) = makeController(store: harness.store, users: harness.users)
        let user = DomainFixtures.adminUser()
        try await harness.users.save(user)
        auth.seed(user: user, password: "secret")
        let operation = try SyncOperation.pending(
            id: SyncOperationID("auth-logout-op"),
            entityType: .customer,
            entityId: "cust-1",
            operationType: .create,
            createdAt: DomainFixtures.referenceDate,
            localVersion: 1
        )
        _ = try await harness.syncOperations.enqueue(operation)
        await controller.signIn(email: user.email, password: "secret")
        await controller.signOut()

        let stored = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
    }

    func testAdminRoleAfterLogin() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.adminUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        guard case .authenticated(let signedIn) = controller.state else {
            return XCTFail("expected authenticated")
        }
        XCTAssertEqual(signedIn.role, .admin)
    }

    func testOperatorRoleAfterLogin() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.operatorUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        guard case .authenticated(let signedIn) = controller.state else {
            return XCTFail("expected authenticated")
        }
        XCTAssertEqual(signedIn.role, .operator)
    }

    func testTechnicianRoleAfterLogin() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        guard case .authenticated(let signedIn) = controller.state else {
            return XCTFail("expected authenticated")
        }
        XCTAssertEqual(signedIn.role, .technician)
    }

    func testRoleChangeRefreshUpdatesSession() async throws {
        let (controller, auth) = makeController()
        var user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")

        user.role = .operator
        auth.updateUser(user)
        await controller.refreshCurrentUser()

        guard case .authenticated(let refreshed) = controller.state else {
            return XCTFail("expected authenticated")
        }
        XCTAssertEqual(refreshed.role, .operator)
    }

    func testAuthStateListenerLogin() async throws {
        let (controller, auth) = makeController()
        await controller.start()
        let user = DomainFixtures.adminUser()
        auth.seed(user: user, password: "secret")

        try await auth.simulateExternalSignIn(user: user)
        try? await Task.sleep(nanoseconds: 50_000_000)

        guard case .authenticated = controller.state else {
            return XCTFail("listener should restore authenticated session")
        }
    }

    func testAuthStateListenerLogout() async throws {
        let (controller, auth) = makeController()
        let user = DomainFixtures.adminUser()
        auth.seed(user: user, password: "secret")
        await controller.signIn(email: user.email, password: "secret")
        await controller.start()

        try await auth.simulateExternalSignOut()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(controller.state, .unauthenticated)
    }

    func testUnauthorizedUserActionStillBlockedByRoleAccessPolicy() {
        let technician = DomainFixtures.technicianUser()
        XCTAssertFalse(
            RoleAccessPolicy.can(.createWorkOrder, as: technician.role)
        )
    }
}
