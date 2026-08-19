import XCTest
@testable import DonanimOperasyonServis

final class ScheduledTimeRangeTests: XCTestCase {

    func testValidatingInitializerAcceptsPositiveWindow() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 4_600)
        let range = ScheduledTimeRange(start: start, end: end)
        XCTAssertNotNil(range)
        XCTAssertEqual(range?.duration, 3_600)
    }

    func testValidatingInitializerRejectsEmptyWindow() {
        let point = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(ScheduledTimeRange(start: point, end: point))
    }

    func testValidatingInitializerRejectsReversedWindow() {
        let start = Date(timeIntervalSince1970: 2_000)
        let end = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(ScheduledTimeRange(start: start, end: end))
    }

    func testContainsMatchesInclusiveEndpoints() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let range = ScheduledTimeRange(uncheckedStart: start, end: end)
        XCTAssertTrue(range.contains(start))
        XCTAssertTrue(range.contains(end))
        XCTAssertTrue(range.contains(Date(timeIntervalSince1970: 1_500)))
        XCTAssertFalse(range.contains(Date(timeIntervalSince1970: 500)))
        XCTAssertFalse(range.contains(Date(timeIntervalSince1970: 2_500)))
    }
}
