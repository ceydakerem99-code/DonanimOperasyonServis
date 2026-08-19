import Foundation
import SwiftData

/// Root dependency container.
///
/// Holds the app's shared SwiftData `ModelContainer`, the local
/// (SwiftData) repositories, and the remote (Firebase) repositories
/// / data sources. ViewModels and use cases receive collaborators
/// via constructor injection — they should never reach into
/// `DIContainer` at call sites.
///
/// Phase 5C wires `SyncManager` to drain the local queue toward
/// the Firebase repositories. Phase 5D adds remote → local
/// reconciliation. Phase 5E adds `ConflictResolver` for explicit
/// `useLocal` / `useRemote` / `unresolved` decisions. Phase 5F
/// adds network reachability, manual retry via `SyncRetryPolicy`,
/// and in-progress recovery. There is still no background scheduler.
///
/// - `userRepository` (and siblings without a `remote` prefix) stay
///   the SwiftData implementations used by the running app.
/// - `remoteUserRepository` (and siblings) are the Firebase
///   implementations, ready for SyncManager to consume.
///
/// `AuthRepository` remains the Phase 3 local-session placeholder.
/// Firebase Auth is Phase 6 and is not wired here.
final class DIContainer: Sendable {

    let modelContainer: ModelContainer
    let localPersistence: LocalPersistence

    /// Outcome of `FirebaseAppBootstrapper.configure()`. Exposed so
    /// diagnostics / a later first-run error surface can inspect it.
    let firebaseBootstrapOutcome: FirebaseAppBootstrapper.Outcome

    let firestoreDataSource: any FirestoreDataSource
    let firebaseStorageDataSource: any FirebaseStorageDataSource
    let workOrderWriteCoordinator: FirebaseWorkOrderWriteCoordinator

    // MARK: Local (SwiftData) repositories — current app surface

    let userRepository: any UserRepository
    let authRepository: any AuthRepository
    let customerRepository: any CustomerRepository
    let workOrderRepository: any WorkOrderRepository
    let workOrderNoteRepository: any WorkOrderNoteRepository
    let workOrderPhotoRepository: any WorkOrderPhotoRepository
    let workOrderLocationRepository: any WorkOrderLocationRepository
    let workOrderStatusHistoryRepository: any WorkOrderStatusHistoryRepository
    let signatureRepository: any SignatureRepository
    let editRequestRepository: any EditRequestRepository
    let notificationRepository: any NotificationRepository
    let syncOperationRepository: any SyncOperationRepository
    let syncConflictRepository: any SyncConflictRepository
    let syncManager: any SyncManaging
    let reconciliationEngine: any Reconciling
    let conflictResolver: any ConflictResolving
    let networkReachability: any NetworkReachabilityProviding
    let syncRecoveryHandler: any SyncRecoveryHandling

    // MARK: Remote (Firebase) repositories — Phase 5 SyncManager input

    let remoteUserRepository: any UserRepository
    let remoteCustomerRepository: any CustomerRepository
    let remoteWorkOrderRepository: any WorkOrderRepository
    let remoteWorkOrderNoteRepository: any WorkOrderNoteRepository
    let remoteWorkOrderPhotoRepository: any WorkOrderPhotoRepository
    let remoteWorkOrderLocationRepository: any WorkOrderLocationRepository
    let remoteWorkOrderStatusHistoryRepository: any WorkOrderStatusHistoryRepository
    let remoteSignatureRepository: any SignatureRepository
    let remoteEditRequestRepository: any EditRequestRepository
    let remoteNotificationRepository: any NotificationRepository

    // MARK: Factories

    /// Live container used by the running application.
    ///
    /// Throws when the disk-backed SwiftData store cannot be opened,
    /// **or** when Firebase is not configured (`GoogleService-Info.plist`
    /// missing or unreadable). Live never falls back to Fake
    /// Firestore/Storage — that path is reserved for `mock()` and
    /// the unit-test harness.
    static func live() throws -> DIContainer {
        let outcome = FirebaseAppBootstrapper.configure()
        switch outcome {
        case .configured, .alreadyConfigured:
            return try DIContainer(
                modelContainer: ModelContainerFactory.live(),
                firestoreDataSource: LiveFirestoreDataSource(),
                storageDataSource: LiveFirebaseStorageDataSource(),
                firebaseBootstrapOutcome: outcome,
                networkReachability: makeLiveReachability()
            )
        case .skippedNoConfig, .skippedInvalidConfig:
            throw FirebaseError.notConfigured
        }
    }

    /// In-memory container for previews and unit tests. Always uses
    /// fake Firebase data sources so tests never touch a real
    /// project, and an in-memory SwiftData store so they never
    /// touch the user's simulator data.
    static func mock() -> DIContainer {
        do {
            return try DIContainer(
                modelContainer: ModelContainerFactory.inMemory(),
                firestoreDataSource: FakeFirestoreDataSource(),
                storageDataSource: FakeFirebaseStorageDataSource(),
                firebaseBootstrapOutcome: .skippedNoConfig,
                networkReachability: FakeNetworkReachability()
            )
        } catch {
            fatalError("Failed to construct in-memory DIContainer: \(error)")
        }
    }

    private init(
        modelContainer: ModelContainer,
        firestoreDataSource: any FirestoreDataSource,
        storageDataSource: any FirebaseStorageDataSource,
        firebaseBootstrapOutcome: FirebaseAppBootstrapper.Outcome,
        networkReachability: any NetworkReachabilityProviding
    ) {
        let store = LocalPersistence(modelContainer: modelContainer)
        self.modelContainer = modelContainer
        self.localPersistence = store
        self.firebaseBootstrapOutcome = firebaseBootstrapOutcome
        self.firestoreDataSource = firestoreDataSource
        self.firebaseStorageDataSource = storageDataSource
        self.workOrderWriteCoordinator = FirebaseWorkOrderWriteCoordinator(
            dataSource: firestoreDataSource
        )

        self.userRepository                     = SwiftDataUserRepository(store: store)
        self.authRepository                     = SwiftDataAuthRepository(store: store)
        self.customerRepository                 = SwiftDataCustomerRepository(store: store)
        self.workOrderRepository                = SwiftDataWorkOrderRepository(store: store)
        self.workOrderNoteRepository            = SwiftDataWorkOrderNoteRepository(store: store)
        self.workOrderPhotoRepository           = SwiftDataWorkOrderPhotoRepository(store: store)
        self.workOrderLocationRepository        = SwiftDataWorkOrderLocationRepository(store: store)
        self.workOrderStatusHistoryRepository   = SwiftDataWorkOrderStatusHistoryRepository(store: store)
        self.signatureRepository                = SwiftDataSignatureRepository(store: store)
        self.editRequestRepository              = SwiftDataEditRequestRepository(store: store)
        self.notificationRepository             = SwiftDataNotificationRepository(store: store)
        self.syncOperationRepository            = SwiftDataSyncOperationRepository(store: store)
        self.syncConflictRepository             = SwiftDataSyncConflictRepository(store: store)

        let localEntities = SyncEntityRepositories(
            users: self.userRepository,
            customers: self.customerRepository,
            workOrders: self.workOrderRepository,
            notes: self.workOrderNoteRepository,
            photos: self.workOrderPhotoRepository,
            locations: self.workOrderLocationRepository,
            statusHistory: self.workOrderStatusHistoryRepository,
            signatures: self.signatureRepository,
            editRequests: self.editRequestRepository,
            notifications: self.notificationRepository
        )
        let remoteEntities = SyncEntityRepositories(
            users: FirebaseUserRepository(dataSource: firestoreDataSource),
            customers: FirebaseCustomerRepository(dataSource: firestoreDataSource),
            workOrders: FirebaseWorkOrderRepository(dataSource: firestoreDataSource),
            notes: FirebaseWorkOrderNoteRepository(dataSource: firestoreDataSource),
            photos: FirebaseWorkOrderPhotoRepository(dataSource: firestoreDataSource),
            locations: FirebaseWorkOrderLocationRepository(dataSource: firestoreDataSource),
            statusHistory: FirebaseWorkOrderStatusHistoryRepository(dataSource: firestoreDataSource),
            signatures: FirebaseSignatureRepository(dataSource: firestoreDataSource),
            editRequests: FirebaseEditRequestRepository(dataSource: firestoreDataSource),
            notifications: FirebaseNotificationRepository(dataSource: firestoreDataSource)
        )
        self.remoteUserRepository                     = remoteEntities.users
        self.remoteCustomerRepository                 = remoteEntities.customers
        self.remoteWorkOrderRepository                = remoteEntities.workOrders
        self.remoteWorkOrderNoteRepository            = remoteEntities.notes
        self.remoteWorkOrderPhotoRepository           = remoteEntities.photos
        self.remoteWorkOrderLocationRepository        = remoteEntities.locations
        self.remoteWorkOrderStatusHistoryRepository   = remoteEntities.statusHistory
        self.remoteSignatureRepository                = remoteEntities.signatures
        self.remoteEditRequestRepository              = remoteEntities.editRequests
        self.remoteNotificationRepository             = remoteEntities.notifications
        self.networkReachability = networkReachability
        self.syncManager = LocalToRemoteSyncManager(
            queue: self.syncOperationRepository,
            conflicts: self.syncConflictRepository,
            local: localEntities,
            remote: remoteEntities,
            reachability: networkReachability
        )
        self.reconciliationEngine = RemoteToLocalReconciliationEngine(
            queue: self.syncOperationRepository,
            conflicts: self.syncConflictRepository,
            local: localEntities,
            remote: remoteEntities
        )
        self.conflictResolver = LocalConflictResolver(
            queue: self.syncOperationRepository,
            conflicts: self.syncConflictRepository,
            local: localEntities,
            remote: remoteEntities
        )
        self.syncRecoveryHandler = LocalSyncRecoveryHandler(
            queue: self.syncOperationRepository
        )
    }

    private static func makeLiveReachability() -> PathMonitorNetworkReachability {
        let monitor = PathMonitorNetworkReachability()
        monitor.start()
        return monitor
    }
}
