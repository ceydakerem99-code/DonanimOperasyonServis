import XCTest
@testable import DonanimOperasyonServis

final class SyncPrinciplesTests: XCTestCase {

    func testLocalAndRemoteSourcesAreDocumented() {
        XCTAssertEqual(SyncPrinciples.localSourceOfTruth, "SwiftData")
        XCTAssertEqual(SyncPrinciples.remoteSource, "Firebase")
    }

    func testSyncOperationIsNotASyncableEntityType() {
        XCTAssertFalse(SyncEntityType.allCases.map(\.rawValue).contains("syncOperation"))
    }
}
