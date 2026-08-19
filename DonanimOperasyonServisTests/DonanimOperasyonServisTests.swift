import XCTest
@testable import DonanimOperasyonServis

final class DonanimOperasyonServisTests: XCTestCase {

    func testDIContainerLiveInstantiates() {
        let container = DIContainer.live()
        XCTAssertNotNil(container)
    }

    func testDIContainerMockInstantiates() {
        let container = DIContainer.mock()
        XCTAssertNotNil(container)
    }

    func testAppLoggerSubsystemMatchesBundleIdentifier() {
        XCTAssertEqual(AppLogger.subsystem, "com.donanimoperasyonservis.app")
    }
}
