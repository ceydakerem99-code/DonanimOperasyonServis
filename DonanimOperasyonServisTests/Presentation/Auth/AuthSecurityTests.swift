import XCTest
@testable import DonanimOperasyonServis

final class AuthSecurityTests: XCTestCase {

    func testPasswordNotStoredInLocalSessionModel() throws {
        let properties = Mirror(reflecting: LocalSessionModel(
            currentUserId: "user-1",
            updatedAt: DomainFixtures.referenceDate
        )).children.map(\.label)
        XCTAssertFalse(properties.contains(where: { $0?.lowercased().contains("password") == true }))
        XCTAssertFalse(properties.contains(where: { $0?.lowercased().contains("token") == true }))
    }

    func testPasswordNotStoredInUserModel() throws {
        let model = UserModel(
            id: "user-1",
            email: "a@b.com",
            fullName: "Test",
            roleRaw: UserRole.admin.rawValue,
            phoneNumberRaw: nil,
            isActive: true,
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
        let properties = Mirror(reflecting: model).children.map(\.label)
        XCTAssertFalse(properties.contains(where: { $0?.lowercased().contains("password") == true }))
        XCTAssertFalse(properties.contains(where: { $0?.lowercased().contains("token") == true }))
    }

    func testFakeAuthRepositoryDoesNotPersistPasswordInSwiftData() async throws {
        let harness = try SwiftDataTestHarness()
        let auth = FakeAuthRepository(store: harness.store, localUsers: harness.users)
        let user = DomainFixtures.adminUser(email: "secure@test.com")
        auth.seed(user: user, password: "super-secret")
        _ = try await auth.signIn(email: user.email, password: "super-secret")

        let sessionId = try await harness.store.currentSessionUserId()
        XCTAssertEqual(sessionId, user.id.rawValue)

        let sessionJSON = String(describing: try await harness.store.currentSessionUserId())
        XCTAssertFalse(sessionJSON.localizedCaseInsensitiveContains("super-secret"))
        XCTAssertFalse(sessionJSON.localizedCaseInsensitiveContains("password"))
    }
}
