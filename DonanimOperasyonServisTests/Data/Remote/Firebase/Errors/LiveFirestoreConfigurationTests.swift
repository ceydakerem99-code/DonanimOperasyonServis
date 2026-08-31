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

    func testDebugSimulatorUsesFirestoreEmulator() {
        #if DEBUG && targetEnvironment(simulator)
        XCTAssertTrue(LiveFirestoreConfiguration.usesLocalEmulator)
        let settings = LiveFirestoreConfiguration.makeSettings()
        XCTAssertEqual(settings.host, "127.0.0.1:8080")
        XCTAssertFalse(settings.isSSLEnabled)
        #else
        XCTAssertFalse(LiveFirestoreConfiguration.usesLocalEmulator)
        #endif
    }
}
