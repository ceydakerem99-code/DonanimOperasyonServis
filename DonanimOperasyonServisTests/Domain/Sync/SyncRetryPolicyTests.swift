import XCTest
@testable import DonanimOperasyonServis

final class SyncRetryPolicyTests: XCTestCase {

    func testRetryableErrors() {
        XCTAssertTrue(SyncRetryPolicy.isRetryable(.networkUnavailable))
        XCTAssertTrue(SyncRetryPolicy.isRetryable(.serverError))
    }

    func testNonRetryableErrors() {
        XCTAssertFalse(SyncRetryPolicy.isRetryable(.unauthorized))
        XCTAssertFalse(SyncRetryPolicy.isRetryable(.invalidPayload))
        XCTAssertFalse(SyncRetryPolicy.isRetryable(.notFound))
        XCTAssertFalse(SyncRetryPolicy.isRetryable(.conflict))
        XCTAssertFalse(SyncRetryPolicy.isRetryable(.unknown(reason: "x")))
    }

    func testExponentialBackoffForFirstThreeRetries() {
        XCTAssertEqual(SyncRetryPolicy.delay(forRetryCount: 0), 2)
        XCTAssertEqual(SyncRetryPolicy.delay(forRetryCount: 1), 4)
        XCTAssertEqual(SyncRetryPolicy.delay(forRetryCount: 2), 8)
    }

    func testShouldRetryUntilMaximumCount() {
        XCTAssertTrue(SyncRetryPolicy.shouldRetry(error: .networkUnavailable, retryCount: 0))
        XCTAssertTrue(SyncRetryPolicy.shouldRetry(error: .serverError, retryCount: 4))
        XCTAssertFalse(SyncRetryPolicy.shouldRetry(error: .networkUnavailable, retryCount: 5))
        XCTAssertFalse(SyncRetryPolicy.shouldRetry(error: .unauthorized, retryCount: 0))
    }

    func testNextRetryDateIsNilWhenCappedOrNonRetryable() {
        let now = DomainFixtures.referenceDate
        XCTAssertEqual(
            SyncRetryPolicy.nextRetryDate(error: .networkUnavailable, retryCount: 0, now: now),
            now.addingTimeInterval(2)
        )
        XCTAssertNil(SyncRetryPolicy.nextRetryDate(error: .conflict, retryCount: 0, now: now))
        XCTAssertNil(SyncRetryPolicy.nextRetryDate(error: .networkUnavailable, retryCount: 5, now: now))
    }

    func testConflictIsNeverRetried() {
        XCTAssertFalse(SyncRetryPolicy.isRetryable(.conflict))
        XCTAssertFalse(SyncRetryPolicy.shouldRetry(error: .conflict, retryCount: 0))
    }
}
