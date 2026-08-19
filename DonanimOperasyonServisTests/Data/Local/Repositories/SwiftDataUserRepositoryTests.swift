import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataUserRepositoryTests: XCTestCase {

    func testSaveThenFetchReturnsIdenticalUser() async throws {
        let harness = try SwiftDataTestHarness()
        let user = DomainFixtures.operatorUser(
            id: UserID("u-1"),
            email: "op@example.com",
            fullName: "Op Kullanıcı"
        )

        try await harness.users.save(user)
        let fetched = try await harness.users.fetch(id: user.id)

        XCTAssertEqual(fetched, user)
    }

    func testFetchUnknownIdThrowsNotFound() async throws {
        let harness = try SwiftDataTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.users.fetch(id: UserID("missing"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "User", id: "missing"))
        }
    }

    func testFindByEmailReturnsNilWhenAbsent() async throws {
        let harness = try SwiftDataTestHarness()
        let found = try await harness.users.findByEmail("nobody@example.com")
        XCTAssertNil(found)
    }

    func testFindByEmailReturnsSavedUser() async throws {
        let harness = try SwiftDataTestHarness()
        let user = DomainFixtures.technicianUser(id: UserID("u-tech"), email: "tech@example.com")
        try await harness.users.save(user)

        let found = try await harness.users.findByEmail("tech@example.com")
        XCTAssertEqual(found, user)
    }

    func testListAndRoleFilter() async throws {
        let harness = try SwiftDataTestHarness()
        let admin = DomainFixtures.adminUser(id: UserID("a"))
        let op = DomainFixtures.operatorUser(id: UserID("b"))
        let tech1 = DomainFixtures.technicianUser(id: UserID("c"), email: "t1@example.com", fullName: "Aylin Teknisyen")
        let tech2 = DomainFixtures.technicianUser(id: UserID("d"), email: "t2@example.com", fullName: "Berk Teknisyen")

        for u in [admin, op, tech1, tech2] { try await harness.users.save(u) }

        let all = try await harness.users.list(role: nil, isActive: nil)
        XCTAssertEqual(Set(all.map(\.id)), Set([admin.id, op.id, tech1.id, tech2.id]))

        let onlyTechnicians = try await harness.users.list(role: .technician, isActive: nil)
        XCTAssertEqual(Set(onlyTechnicians.map(\.id)), Set([tech1.id, tech2.id]))
    }

    func testDeleteRemovesUser() async throws {
        let harness = try SwiftDataTestHarness()
        let user = DomainFixtures.operatorUser()
        try await harness.users.save(user)

        try await harness.users.delete(id: user.id)

        await XCTAssertThrowsErrorAsync(
            try await harness.users.fetch(id: user.id)
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "User", id: user.id.rawValue))
        }
    }

    func testSaveUpdatesInPlace() async throws {
        let harness = try SwiftDataTestHarness()
        var user = DomainFixtures.operatorUser(id: UserID("u-1"), fullName: "İlk Ad")
        try await harness.users.save(user)

        user.fullName = "Yeni Ad"
        user.updatedAt = DomainFixtures.referenceDate.addingTimeInterval(600)
        try await harness.users.save(user)

        let fetched = try await harness.users.fetch(id: user.id)
        XCTAssertEqual(fetched.fullName, "Yeni Ad")

        let all = try await harness.users.list(role: nil, isActive: nil)
        XCTAssertEqual(all.count, 1, "upsert must not create a duplicate")
    }
}
