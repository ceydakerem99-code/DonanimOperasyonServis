import XCTest
@testable import DonanimOperasyonServis

final class DonanimOperasyonServisTests: XCTestCase {

    func testDIContainerLiveFailsFastWhenFirebaseIsUnconfigured() {
        XCTAssertThrowsError(try DIContainer.live()) { error in
            XCTAssertEqual(error as? FirebaseError, .notConfigured)
        }
    }

    func testDIContainerMockStillUsesFakeFirebase() {
        let container = DIContainer.mock()
        XCTAssertTrue(container.firestoreDataSource is FakeFirestoreDataSource)
        XCTAssertTrue(container.firebaseStorageDataSource is FakeFirebaseStorageDataSource)
        XCTAssertEqual(container.firebaseBootstrapOutcome, .skippedNoConfig)
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
        XCTAssertNotNil(container.syncOperationRepository)
        XCTAssertNotNil(container.syncConflictRepository)
        XCTAssertNotNil(container.syncManager)
        XCTAssertNotNil(container.remoteUserRepository)
        XCTAssertNotNil(container.remoteCustomerRepository)
        XCTAssertNotNil(container.remoteWorkOrderRepository)
        XCTAssertNotNil(container.remoteWorkOrderNoteRepository)
        XCTAssertNotNil(container.remoteWorkOrderPhotoRepository)
        XCTAssertNotNil(container.remoteWorkOrderLocationRepository)
        XCTAssertNotNil(container.remoteWorkOrderStatusHistoryRepository)
        XCTAssertNotNil(container.remoteSignatureRepository)
        XCTAssertNotNil(container.remoteEditRequestRepository)
        XCTAssertNotNil(container.remoteNotificationRepository)
        XCTAssertNotNil(container.firestoreDataSource)
        XCTAssertNotNil(container.firebaseStorageDataSource)
        XCTAssertEqual(container.firebaseBootstrapOutcome, .skippedNoConfig)
    }

    func testAppLoggerSubsystemMatchesBundleIdentifier() {
        XCTAssertEqual(AppLogger.subsystem, "com.donanimoperasyonservis.app")
    }
}
