import Foundation
@testable import DonanimOperasyonServis

/// Builds a set of Firebase repositories wired against a fresh
/// in-memory `FakeFirestoreDataSource` / `FakeFirebaseStorageDataSource`.
/// Each test case should allocate its own harness so state never
/// leaks across tests.
struct FirebaseTestHarness {

    let firestore: FakeFirestoreDataSource
    let storage: FakeFirebaseStorageDataSource
    let users: FirebaseUserRepository
    let customers: FirebaseCustomerRepository
    let workOrders: FirebaseWorkOrderRepository
    let notes: FirebaseWorkOrderNoteRepository
    let photos: FirebaseWorkOrderPhotoRepository
    let locations: FirebaseWorkOrderLocationRepository
    let statusHistory: FirebaseWorkOrderStatusHistoryRepository
    let signatures: FirebaseSignatureRepository
    let editRequests: FirebaseEditRequestRepository
    let notifications: FirebaseNotificationRepository
    let writeCoordinator: FirebaseWorkOrderWriteCoordinator

    init() {
        let firestore = FakeFirestoreDataSource()
        let storage = FakeFirebaseStorageDataSource()
        self.firestore = firestore
        self.storage = storage
        self.users = FirebaseUserRepository(dataSource: firestore)
        self.customers = FirebaseCustomerRepository(dataSource: firestore)
        self.workOrders = FirebaseWorkOrderRepository(dataSource: firestore)
        self.notes = FirebaseWorkOrderNoteRepository(dataSource: firestore)
        self.photos = FirebaseWorkOrderPhotoRepository(dataSource: firestore)
        self.locations = FirebaseWorkOrderLocationRepository(dataSource: firestore)
        self.statusHistory = FirebaseWorkOrderStatusHistoryRepository(dataSource: firestore)
        self.signatures = FirebaseSignatureRepository(dataSource: firestore)
        self.editRequests = FirebaseEditRequestRepository(dataSource: firestore)
        self.notifications = FirebaseNotificationRepository(dataSource: firestore)
        self.writeCoordinator = FirebaseWorkOrderWriteCoordinator(dataSource: firestore)
    }
}
