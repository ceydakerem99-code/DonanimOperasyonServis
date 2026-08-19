import XCTest
@testable import DonanimOperasyonServis

final class SyncErrorMappingTests: XCTestCase {

    func testNetworkAndServerInfrastructure() {
        XCTAssertEqual(
            SyncErrorMapping.from(DomainError.infrastructure(underlying: "firebase.networkUnavailable")),
            .networkUnavailable
        )
        XCTAssertEqual(
            SyncErrorMapping.from(DomainError.infrastructure(underlying: "firebase.serverError")),
            .serverError
        )
        XCTAssertEqual(
            SyncErrorMapping.from(DomainError.infrastructure(underlying: "firebase.permissionDenied")),
            .unauthorized
        )
        XCTAssertEqual(
            SyncErrorMapping.from(DomainError.infrastructure(underlying: "firebase.encodingFailed: x")),
            .invalidPayload
        )
    }

    func testDomainCases() {
        XCTAssertEqual(SyncErrorMapping.from(DomainError.notFound(entity: "Customer", id: "1")), .notFound)
        XCTAssertEqual(SyncErrorMapping.from(DomainError.invalidData(reason: "x")), .invalidPayload)
        XCTAssertEqual(
            SyncErrorMapping.from(DomainError.unauthorized(action: .createWorkOrder)),
            .unauthorized
        )
        XCTAssertEqual(SyncErrorMapping.from(SyncConflictDetected(
            localVersion: 1,
            remoteVersion: 2,
            localReference: nil,
            remoteReference: nil
        )), .conflict)
    }
}
