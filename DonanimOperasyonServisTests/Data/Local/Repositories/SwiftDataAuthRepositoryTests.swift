import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataAuthRepositoryTests: XCTestCase {

    func testCurrentUserIsNilBeforeSignIn() async throws {
        let harness = try SwiftDataTestHarness()
        let user = try await harness.auth.currentUser()
        XCTAssertNil(user)
    }

    func testSignInSetsCurrentUser() async throws {
        let harness = try SwiftDataTestHarness()
        let seeded = DomainFixtures.technicianUser(email: "t@example.com")
        try await harness.users.save(seeded)

        let signedIn = try await harness.auth.signIn(email: "t@example.com", password: "ignored-in-v3")
        XCTAssertEqual(signedIn, seeded)

        let current = try await harness.auth.currentUser()
        XCTAssertEqual(current, seeded)
    }

    func testSignInThrowsForUnknownEmail() async throws {
        let harness = try SwiftDataTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.auth.signIn(email: "ghost@example.com", password: "x")
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "User", id: "ghost@example.com"))
        }
    }

    func testSignOutClearsCurrentUser() async throws {
        let harness = try SwiftDataTestHarness()
        let user = DomainFixtures.operatorUser(email: "op@example.com")
        try await harness.users.save(user)
        _ = try await harness.auth.signIn(email: "op@example.com", password: "x")

        try await harness.auth.signOut()
        let current = try await harness.auth.currentUser()
        XCTAssertNil(current)
    }

    func testCurrentUserGracefullyHandlesDeletedSessionOwner() async throws {
        let harness = try SwiftDataTestHarness()
        let user = DomainFixtures.operatorUser()
        try await harness.users.save(user)
        _ = try await harness.auth.signIn(email: user.email, password: "x")

        // Delete the user out from under the session pointer.
        try await harness.users.delete(id: user.id)

        let current = try await harness.auth.currentUser()
        XCTAssertNil(current, "a stale session must not brick the app")
    }
}
