import XCTest
@testable import DonanimOperasyonServis

final class FirebaseErrorMappingTests: XCTestCase {

    func testIdentityWhenAlreadyFirebaseError() {
        let original = FirebaseError.networkUnavailable
        XCTAssertEqual(FirebaseError.map(original), original)
    }

    func testDecodingErrorMapsToDecodingFailed() {
        let error = DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "bad")
        )
        if case .decodingFailed = FirebaseError.map(error) {
            // ok
        } else {
            XCTFail("expected decodingFailed, got \(FirebaseError.map(error))")
        }
    }

    func testEncodingErrorMapsToEncodingFailed() {
        struct Dummy: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    0,
                    .init(codingPath: [], debugDescription: "nope")
                )
            }
        }
        do {
            _ = try JSONEncoder().encode(Dummy())
            XCTFail("expected encode to throw")
        } catch {
            if case .encodingFailed = FirebaseError.map(error) {
                // ok
            } else {
                XCTFail("expected encodingFailed, got \(FirebaseError.map(error))")
            }
        }
    }

    func testUnknownNSErrorFallsBackToUnknown() {
        let nsError = NSError(domain: "SomeOtherDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "boom"
        ])
        XCTAssertEqual(FirebaseError.map(nsError), .unknown(reason: "boom"))
    }

    func testFirestoreNotFoundCodeMapsToNotFound() {
        let nsError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 5, // FirestoreErrorCode.notFound
            userInfo: [NSLocalizedDescriptionKey: "missing"]
        )
        XCTAssertEqual(FirebaseError.map(nsError), .notFound)
    }

    func testFirestorePermissionDeniedAndUnauthenticatedMapToPermissionDenied() {
        let denied = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 7, // permissionDenied
            userInfo: [NSLocalizedDescriptionKey: "nope"]
        )
        XCTAssertEqual(FirebaseError.map(denied), .permissionDenied)

        let unauth = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 16, // unauthenticated
            userInfo: [NSLocalizedDescriptionKey: "nope"]
        )
        XCTAssertEqual(FirebaseError.map(unauth), .permissionDenied)
    }

    func testFirestoreUnavailableMapsToNetworkUnavailable() {
        let nsError = NSError(
            domain: "FIRFirestoreErrorDomain",
            code: 14, // unavailable
            userInfo: [NSLocalizedDescriptionKey: "offline"]
        )
        XCTAssertEqual(FirebaseError.map(nsError), .networkUnavailable)
    }

    func testMapNotFoundBecomesDomainNotFound() {
        let mapped = FirebaseRepositoryMapper.mapNotFound(
            FirebaseError.notFound,
            entity: "User",
            id: "u-1"
        )
        XCTAssertEqual(mapped as? DomainError, .notFound(entity: "User", id: "u-1"))
    }

    func testMapNotFoundLeavesOtherErrorsUntouched() {
        let mapped = FirebaseRepositoryMapper.mapNotFound(
            FirebaseError.networkUnavailable,
            entity: "User",
            id: "u-1"
        )
        XCTAssertEqual(mapped as? FirebaseError, .networkUnavailable)
    }
}
