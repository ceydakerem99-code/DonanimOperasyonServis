import XCTest
@testable import DonanimOperasyonServis

final class FirebaseUserRepositoryTests: XCTestCase {

    func testSaveThenFetch() async throws {
        let harness = FirebaseTestHarness()
        let user = DomainFixtures.operatorUser()
        try await harness.users.save(user)
        let fetched = try await harness.users.fetch(id: user.id)
        XCTAssertEqual(fetched, user)
    }

    func testFetchUnknownThrowsNotFound() async throws {
        let harness = FirebaseTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.users.fetch(id: UserID("missing"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "User", id: "missing"))
        }
    }

    func testFindByEmail() async throws {
        let harness = FirebaseTestHarness()
        let user = DomainFixtures.technicianUser(email: "tech@example.com")
        try await harness.users.save(user)
        let found = try await harness.users.findByEmail("tech@example.com")
        XCTAssertEqual(found, user)
        let missing = try await harness.users.findByEmail("nobody@example.com")
        XCTAssertNil(missing)
    }

    func testListRoleAndActiveFilters() async throws {
        let harness = FirebaseTestHarness()
        let admin = DomainFixtures.adminUser(id: UserID("a"))
        let op = DomainFixtures.operatorUser(id: UserID("b"))
        let tech = DomainFixtures.technicianUser(id: UserID("c"), email: "t@example.com")
        var inactive = DomainFixtures.technicianUser(id: UserID("d"), email: "x@example.com", fullName: "Pasif")
        inactive.isActive = false
        for user in [admin, op, tech, inactive] { try await harness.users.save(user) }

        let technicians = try await harness.users.list(role: .technician, isActive: true)
        XCTAssertEqual(technicians.map(\.id), [tech.id])
    }

    func testDelete() async throws {
        let harness = FirebaseTestHarness()
        let user = DomainFixtures.operatorUser()
        try await harness.users.save(user)
        try await harness.users.delete(id: user.id)
        await XCTAssertThrowsErrorAsync(try await harness.users.fetch(id: user.id)) { _ in }
    }

    func testInvalidDocumentThrowsFirebaseError() async throws {
        let harness = FirebaseTestHarness()
        try await harness.firestore.seedRaw(
            collection: .users,
            id: "bad",
            json: [
                "id": "bad",
                "email": "x@y.com",
                "fullName": "X",
                "role": "not-a-role",
                "isActive": true,
                "createdAt": 1_700_000_000_000,
                "updatedAt": 1_700_000_000_000
            ]
        )
        await XCTAssertThrowsErrorAsync(
            try await harness.users.fetch(id: UserID("bad"))
        ) { error in
            if case .invalidData(let reason) = error as? DomainError {
                XCTAssertTrue(reason.contains("User.decodeFailed"))
            } else {
                XCTFail("expected DomainError.invalidData, got \(error)")
            }
        }
    }
}
