import XCTest
@testable import DonanimOperasyonServis

final class FirebaseAuthRepositoryTests: XCTestCase {

    func testSignInLoadsFirestoreUserByUID() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let user = DomainFixtures.adminUser(id: UserID("firebase-uid-1"))
        try await harness.users.save(user)
        authService.register(email: user.email, uid: user.id.rawValue)
        let localStore = try SwiftDataTestHarness()
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store,
            clock: { DomainFixtures.referenceDate }
        )

        let signedIn = try await repository.signIn(email: user.email, password: "password")
        XCTAssertEqual(signedIn.id, user.id)
        let sessionId = try await localStore.store.currentSessionUserId()
        XCTAssertEqual(sessionId, user.id.rawValue)
    }

    func testSignInMissingFirestoreUserDoesNotCreateSession() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let user = DomainFixtures.adminUser(id: UserID("missing-doc-uid"))
        authService.register(email: user.email, uid: user.id.rawValue)
        let localStore = try SwiftDataTestHarness()
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store
        )

        await XCTAssertThrowsErrorAsync(
            try await repository.signIn(email: user.email, password: "password")
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .authenticationFailed(.userDocumentMissing)
            )
        }

        let sessionId = try await localStore.store.currentSessionUserId()
        XCTAssertNil(sessionId)
        let currentUID = authService.currentUID
        XCTAssertNil(currentUID)
    }

    func testSignInBootstrapsFirstAdminWhenFirestoreProfileMissing() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let uid = FirstAdminBootstrap.uid
        let email = "bootstrap-admin@test.com"
        authService.register(email: email, uid: uid, displayName: "Bootstrap Admin")
        let localStore = try SwiftDataTestHarness()
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store,
            clock: { DomainFixtures.referenceDate }
        )

        let signedIn = try await repository.signIn(email: email, password: "password")

        XCTAssertEqual(signedIn.id.rawValue, uid)
        XCTAssertEqual(signedIn.role, .admin)
        XCTAssertEqual(signedIn.email, email)
        XCTAssertEqual(signedIn.fullName, "Bootstrap Admin")
        XCTAssertTrue(signedIn.isActive)

        let remote = try await harness.users.fetch(id: UserID(uid))
        XCTAssertEqual(remote.role, .admin)
        let sessionId = try await localStore.store.currentSessionUserId()
        XCTAssertEqual(sessionId, uid)
    }

    func testSignInBootstrapsAdminPanelEmailEvenWhenUIDNotAllowlisted() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let uid = "unexpected-admin-uid-xyz"
        let email = "adminpanel@dops.com"
        authService.register(email: email, uid: uid, displayName: "Admin Panel")
        let localStore = try SwiftDataTestHarness()
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store,
            clock: { DomainFixtures.referenceDate }
        )

        let signedIn = try await repository.signIn(email: email, password: "password")

        XCTAssertEqual(signedIn.id.rawValue, uid)
        XCTAssertEqual(signedIn.role, .admin)
        XCTAssertEqual(signedIn.email, email)
        let remote = try await harness.users.fetch(id: UserID(uid))
        XCTAssertEqual(remote.email, email)
    }

    func testLogoutClearsSessionOnly() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let user = DomainFixtures.operatorUser(id: UserID("logout-uid"))
        try await harness.users.save(user)
        authService.register(email: user.email, uid: user.id.rawValue)
        let localStore = try SwiftDataTestHarness()
        let customer = DomainFixtures.customer()
        try await localStore.customers.save(customer)
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store
        )
        _ = try await repository.signIn(email: user.email, password: "password")
        try await repository.signOut()

        let sessionId = try await localStore.store.currentSessionUserId()
        let storedCustomer = try await localStore.customers.fetch(id: customer.id)
        XCTAssertNil(sessionId)
        XCTAssertNotNil(storedCustomer)
    }
}
