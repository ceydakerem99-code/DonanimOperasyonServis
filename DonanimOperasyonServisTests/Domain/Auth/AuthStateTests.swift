import XCTest
@testable import DonanimOperasyonServis

final class AuthStateTests: XCTestCase {

    func testAuthStateEquality() {
        let user = DomainFixtures.adminUser()
        XCTAssertEqual(AuthState.authenticated(user), AuthState.authenticated(user))
        XCTAssertEqual(AuthState.checkingSession, AuthState.checkingSession)
        XCTAssertEqual(AuthState.unauthenticated, AuthState.unauthenticated)
        XCTAssertEqual(
            AuthState.authenticationError(.authenticationFailed(.invalidCredentials)),
            AuthState.authenticationError(.authenticationFailed(.invalidCredentials))
        )
    }
}
