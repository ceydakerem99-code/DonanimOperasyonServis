import Foundation
@testable import DonanimOperasyonServis

/// Small helper that constructs an in-memory SwiftData stack with the
/// full production schema, plus every SwiftData-backed repository
/// wired against the shared `LocalPersistence` actor.
///
/// Each test case should allocate one `SwiftDataTestHarness` in
/// `setUp()` (or lazily in the test body) so tests never share
/// storage state.
struct SwiftDataTestHarness {

    let store: LocalPersistence
    let users: SwiftDataUserRepository
    let auth: SwiftDataAuthRepository
    let customers: SwiftDataCustomerRepository
    let workOrders: SwiftDataWorkOrderRepository
    let notes: SwiftDataWorkOrderNoteRepository
    let photos: SwiftDataWorkOrderPhotoRepository
    let locations: SwiftDataWorkOrderLocationRepository
    let statusHistory: SwiftDataWorkOrderStatusHistoryRepository
    let signatures: SwiftDataSignatureRepository
    let editRequests: SwiftDataEditRequestRepository
    let notifications: SwiftDataNotificationRepository

    init(clock: @Sendable @escaping () -> Date = { DomainFixtures.referenceDate }) throws {
        let container = try ModelContainerFactory.inMemory()
        let store = LocalPersistence(modelContainer: container)
        self.store = store
        self.users = SwiftDataUserRepository(store: store)
        self.auth = SwiftDataAuthRepository(store: store, clock: clock)
        self.customers = SwiftDataCustomerRepository(store: store)
        self.workOrders = SwiftDataWorkOrderRepository(store: store)
        self.notes = SwiftDataWorkOrderNoteRepository(store: store)
        self.photos = SwiftDataWorkOrderPhotoRepository(store: store)
        self.locations = SwiftDataWorkOrderLocationRepository(store: store)
        self.statusHistory = SwiftDataWorkOrderStatusHistoryRepository(store: store)
        self.signatures = SwiftDataSignatureRepository(store: store)
        self.editRequests = SwiftDataEditRequestRepository(store: store)
        self.notifications = SwiftDataNotificationRepository(store: store)
    }
}
