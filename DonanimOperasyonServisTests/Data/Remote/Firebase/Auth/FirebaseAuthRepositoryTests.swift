import XCTest
@testable import DonanimOperasyonServis

final class FirebaseAuthRepositoryTests: XCTestCase {

    func testSignInLoadsFirestoreUserByUID() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let user = DomainFixtures.adminUser(id: UserID("firebase-uid-1"))
        try await harness.users.save(user)
        await authService.register(email: user.email, uid: user.id.rawValue)
        let localStore = try SwiftDataTestHarness()
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store,
            clock: { DomainFixtures.referenceDate }
        )

        let signedIn = try await repository.signIn(email: user.email, password: "any")
        XCTAssertEqual(signedIn.id, user.id)
        let sessionId = try await localStore.store.currentSessionUserId()
        XCTAssertEqual(sessionId, user.id.rawValue)
    }

    func testSignInMissingFirestoreUserDoesNotCreateSession() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let user = DomainFixtures.adminUser(id: UserID("missing-doc-uid"))
        await authService.register(email: user.email, uid: user.id.rawValue)
        let localStore = try SwiftDataTestHarness()
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store
        )

        await XCTAssertThrowsErrorAsync(
            try await repository.signIn(email: user.email, password: "any")
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

    func testLogoutClearsSessionOnly() async throws {
        let harness = FirebaseTestHarness()
        let authService = FakeFirebaseAuthService()
        let user = DomainFixtures.operatorUser(id: UserID("logout-uid"))
        try await harness.users.save(user)
        await authService.register(email: user.email, uid: user.id.rawValue)
        let localStore = try SwiftDataTestHarness()
        let customer = DomainFixtures.customer()
        try await localStore.customers.save(customer)
        let repository = FirebaseAuthRepository(
            authService: authService,
            remoteUsers: harness.users,
            localUsers: localStore.users,
            store: localStore.store
        )
        _ = try await repository.signIn(email: user.email, password: "any")
        try await repository.signOut()

        let sessionId = try await localStore.store.currentSessionUserId()
        let storedCustomer = try await localStore.customers.fetch(id: customer.id)
        XCTAssertNil(sessionId)
        XCTAssertNotNil(storedCustomer)
    }
}
