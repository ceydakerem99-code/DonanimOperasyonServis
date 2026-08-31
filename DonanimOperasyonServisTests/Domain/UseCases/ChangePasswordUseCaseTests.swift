import XCTest
@testable import DonanimOperasyonServis

final class ChangePasswordUseCaseTests: XCTestCase {

    func testSuccessfulPasswordChange() async throws {
        let auth = FakeAuthRepository()
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "old-pass-1")
        _ = try await auth.signIn(email: user.email, password: "old-pass-1")

        let useCase = ChangePasswordUseCase(
            authRepository: auth,
            networkReachability: FakeNetworkReachability(isReachable: true)
        )
        try await useCase.execute(
            currentPassword: "old-pass-1",
            newPassword: "new-pass-1",
            confirmation: "new-pass-1"
        )

        _ = try await auth.signIn(email: user.email, password: "new-pass-1")
        do {
            _ = try await auth.signIn(email: user.email, password: "old-pass-1")
            XCTFail("old password should fail")
        } catch let error as DomainError {
            XCTAssertEqual(error, .authenticationFailed(.invalidCredentials))
        }
    }

    func testWrongCurrentPasswordFails() async throws {
        let auth = FakeAuthRepository()
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "correct")
        _ = try await auth.signIn(email: user.email, password: "correct")

        let useCase = ChangePasswordUseCase(
            authRepository: auth,
            networkReachability: FakeNetworkReachability(isReachable: true)
        )
        do {
            try await useCase.execute(
                currentPassword: "wrong",
                newPassword: "new-pass-1",
                confirmation: "new-pass-1"
            )
            XCTFail("expected failure")
        } catch let error as DomainError {
            XCTAssertEqual(error, .authenticationFailed(.invalidCredentials))
        }
    }

    func testMismatchedConfirmationFails() async throws {
        let auth = FakeAuthRepository()
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "correct1")
        _ = try await auth.signIn(email: user.email, password: "correct1")

        let useCase = ChangePasswordUseCase(
            authRepository: auth,
            networkReachability: FakeNetworkReachability(isReachable: true)
        )
        do {
            try await useCase.execute(
                currentPassword: "correct1",
                newPassword: "new-pass-1",
                confirmation: "new-pass-2"
            )
            XCTFail("expected failure")
        } catch let error as DomainError {
            XCTAssertEqual(error, .authenticationFailed(.passwordsDoNotMatch))
        }
    }

    func testShortPasswordFails() async throws {
        let auth = FakeAuthRepository()
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "correct1")
        _ = try await auth.signIn(email: user.email, password: "correct1")

        let useCase = ChangePasswordUseCase(
            authRepository: auth,
            networkReachability: FakeNetworkReachability(isReachable: true)
        )
        do {
            try await useCase.execute(
                currentPassword: "correct1",
                newPassword: "123",
                confirmation: "123"
            )
            XCTFail("expected failure")
        } catch let error as DomainError {
            XCTAssertEqual(error, .authenticationFailed(.weakPassword))
        }
    }

    func testSameAsCurrentFails() async throws {
        let auth = FakeAuthRepository()
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "same-pass")
        _ = try await auth.signIn(email: user.email, password: "same-pass")

        let useCase = ChangePasswordUseCase(
            authRepository: auth,
            networkReachability: FakeNetworkReachability(isReachable: true)
        )
        do {
            try await useCase.execute(
                currentPassword: "same-pass",
                newPassword: "same-pass",
                confirmation: "same-pass"
            )
            XCTFail("expected failure")
        } catch let error as DomainError {
            XCTAssertEqual(error, .authenticationFailed(.sameAsCurrentPassword))
        }
    }

    func testOfflineFailsWithNetworkUnavailable() async throws {
        let auth = FakeAuthRepository()
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "correct1")
        _ = try await auth.signIn(email: user.email, password: "correct1")

        let useCase = ChangePasswordUseCase(
            authRepository: auth,
            networkReachability: FakeNetworkReachability(isReachable: false)
        )
        do {
            try await useCase.execute(
                currentPassword: "correct1",
                newPassword: "new-pass-1",
                confirmation: "new-pass-1"
            )
            XCTFail("expected failure")
        } catch let error as DomainError {
            XCTAssertEqual(error, .authenticationFailed(.networkUnavailable))
        }
    }
}
