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
/// Phase 4 keeps **both** local and remote repository families
/// wired, without composing them. Phase 5 will introduce
/// `SyncManager` that reads from both. Until then:
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
    /// Throws when the disk-backed SwiftData store cannot be opened.
    /// Firebase is bootstrapped opportunistically: a missing
    /// `GoogleService-Info.plist` (the Phase 4 default) falls back
    /// to in-memory fakes so the app still launches.
    static func live() throws -> DIContainer {
        let outcome = FirebaseAppBootstrapper.configure()
        let firestore: any FirestoreDataSource
        let storage: any FirebaseStorageDataSource
        switch outcome {
        case .configured, .alreadyConfigured:
            firestore = LiveFirestoreDataSource()
            storage = LiveFirebaseStorageDataSource()
        case .skippedNoConfig, .skippedInvalidConfig:
            firestore = FakeFirestoreDataSource()
            storage = FakeFirebaseStorageDataSource()
        }
        return try DIContainer(
            modelContainer: ModelContainerFactory.live(),
            firestoreDataSource: firestore,
            storageDataSource: storage,
            firebaseBootstrapOutcome: outcome
        )
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
                firebaseBootstrapOutcome: .skippedNoConfig
            )
        } catch {
            fatalError("Failed to construct in-memory DIContainer: \(error)")
        }
    }

    private init(
        modelContainer: ModelContainer,
        firestoreDataSource: any FirestoreDataSource,
        storageDataSource: any FirebaseStorageDataSource,
        firebaseBootstrapOutcome: FirebaseAppBootstrapper.Outcome
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

        self.remoteUserRepository                     = FirebaseUserRepository(dataSource: firestoreDataSource)
        self.remoteCustomerRepository                 = FirebaseCustomerRepository(dataSource: firestoreDataSource)
        self.remoteWorkOrderRepository                = FirebaseWorkOrderRepository(dataSource: firestoreDataSource)
        self.remoteWorkOrderNoteRepository            = FirebaseWorkOrderNoteRepository(dataSource: firestoreDataSource)
        self.remoteWorkOrderPhotoRepository           = FirebaseWorkOrderPhotoRepository(dataSource: firestoreDataSource)
        self.remoteWorkOrderLocationRepository        = FirebaseWorkOrderLocationRepository(dataSource: firestoreDataSource)
        self.remoteWorkOrderStatusHistoryRepository   = FirebaseWorkOrderStatusHistoryRepository(dataSource: firestoreDataSource)
        self.remoteSignatureRepository                = FirebaseSignatureRepository(dataSource: firestoreDataSource)
        self.remoteEditRequestRepository              = FirebaseEditRequestRepository(dataSource: firestoreDataSource)
        self.remoteNotificationRepository             = FirebaseNotificationRepository(dataSource: firestoreDataSource)
    }
}
