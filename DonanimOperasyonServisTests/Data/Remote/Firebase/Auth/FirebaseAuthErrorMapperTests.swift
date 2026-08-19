import XCTest
import FirebaseAuth
@testable import DonanimOperasyonServis

final class FirebaseAuthErrorMapperTests: XCTestCase {

    func testInvalidCredentialsMapping() {
        let error = NSError(
            domain: AuthErrorDomain,
            code: AuthErrorCode.wrongPassword.rawValue
        )
        XCTAssertEqual(
            FirebaseAuthErrorMapper.map(error),
            .authenticationFailed(.invalidCredentials)
        )
    }

    func testUserNotFoundMapping() {
        let error = NSError(
            domain: AuthErrorDomain,
            code: AuthErrorCode.userNotFound.rawValue
        )
        XCTAssertEqual(
            FirebaseAuthErrorMapper.map(error),
            .authenticationFailed(.invalidCredentials)
        )
    }

    func testNetworkUnavailableMapping() {
        let error = NSError(
            domain: AuthErrorDomain,
            code: AuthErrorCode.networkError.rawValue
        )
        XCTAssertEqual(
            FirebaseAuthErrorMapper.map(error),
            .authenticationFailed(.networkUnavailable)
        )
    }

    func testTooManyRequestsMapping() {
        let error = NSError(
            domain: AuthErrorDomain,
            code: AuthErrorCode.tooManyRequests.rawValue
        )
        XCTAssertEqual(
            FirebaseAuthErrorMapper.map(error),
            .authenticationFailed(.tooManyRequests)
        )
    }

    func testUnauthorizedMapping() {
        let error = NSError(
            domain: AuthErrorDomain,
            code: AuthErrorCode.userDisabled.rawValue
        )
        XCTAssertEqual(
            FirebaseAuthErrorMapper.map(error),
            .authenticationFailed(.unauthorized)
        )
    }
}
