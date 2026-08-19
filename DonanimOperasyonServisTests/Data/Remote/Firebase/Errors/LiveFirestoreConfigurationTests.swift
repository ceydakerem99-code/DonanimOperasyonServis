import XCTest
@testable import DonanimOperasyonServis

final class LiveFirestoreConfigurationTests: XCTestCase {

    func testPersistentCacheIsDisabled() {
        XCTAssertFalse(LiveFirestoreConfiguration.isPersistentCacheEnabled)
        XCTAssertTrue(LiveFirestoreConfiguration.usesMemoryCacheSettings)
    }

    func testReadsUseServerSource() {
        XCTAssertTrue(LiveFirestoreConfiguration.usesServerReadSource)
    }

    func testSetAwaitsDocumentWrites() {
        XCTAssertTrue(LiveFirestoreConfiguration.awaitsDocumentWrites)
    }
}
