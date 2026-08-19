import XCTest
@testable import DonanimOperasyonServis

final class DonanimOperasyonServisTests: XCTestCase {

    func testDIContainerLiveInstantiates() throws {
        let container = try DIContainer.live()
        XCTAssertNotNil(container)
        XCTAssertNotNil(container.modelContainer)
    }

    func testDIContainerMockInstantiates() {
        let container = DIContainer.mock()
        XCTAssertNotNil(container)
        XCTAssertNotNil(container.modelContainer)
    }

    func testDIContainerMockWiresEveryRepository() {
        let container = DIContainer.mock()
        XCTAssertNotNil(container.userRepository)
        XCTAssertNotNil(container.authRepository)
        XCTAssertNotNil(container.customerRepository)
        XCTAssertNotNil(container.workOrderRepository)
        XCTAssertNotNil(container.workOrderNoteRepository)
        XCTAssertNotNil(container.workOrderPhotoRepository)
        XCTAssertNotNil(container.workOrderLocationRepository)
        XCTAssertNotNil(container.workOrderStatusHistoryRepository)
        XCTAssertNotNil(container.signatureRepository)
        XCTAssertNotNil(container.editRequestRepository)
        XCTAssertNotNil(container.notificationRepository)
    }

    func testAppLoggerSubsystemMatchesBundleIdentifier() {
        XCTAssertEqual(AppLogger.subsystem, "com.donanimoperasyonservis.app")
    }
}
