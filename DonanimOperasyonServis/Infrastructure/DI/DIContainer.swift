import Foundation
import SwiftData

/// Root dependency container.
///
/// Holds the app's shared SwiftData `ModelContainer` and the
/// repository implementations wired against it. ViewModels and use
/// cases receive their collaborators via constructor injection —
/// they should never reach into `DIContainer` at call sites, so
/// tests can substitute individual repositories without going
/// through the container.
///
/// - Note: `DIContainer` is a `final class` and not `@Observable`.
///   It is created once at app launch and shared through the SwiftUI
///   environment via ``DIContainerKey``.
final class DIContainer: Sendable {

    /// The SwiftData container backing every persistence repository
    /// in this DIContainer. Kept accessible so future subsystems
    /// (e.g. `@Query` in previews) can attach to the same store.
    let modelContainer: ModelContainer

    /// Actor-isolated `ModelContext` wrapper. Exposed for future
    /// use-cases that need multi-repository transactional writes.
    let localPersistence: LocalPersistence

    // MARK: Repository handles (Domain protocol types)

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

    // MARK: Factories

    /// Live container used by the running application.
    ///
    /// Throws when the disk-backed SwiftData store cannot be opened
    /// (schema incompatibility, disk full, etc.). Callers at app
    /// launch may either surface the error to the user or terminate
    /// — there is no meaningful in-app recovery for a broken local
    /// store in v3.
    static func live() throws -> DIContainer {
        try DIContainer(modelContainer: ModelContainerFactory.live())
    }

    /// In-memory container for previews and unit tests. Traps on
    /// failure because an in-memory store construction is not
    /// expected to fail on a running device; if it does, the test
    /// harness itself is broken and a fail-fast is the correct
    /// signal.
    static func mock() -> DIContainer {
        do {
            return try DIContainer(modelContainer: ModelContainerFactory.inMemory())
        } catch {
            fatalError("Failed to construct in-memory SwiftData container: \(error)")
        }
    }

    private init(modelContainer: ModelContainer) {
        let store = LocalPersistence(modelContainer: modelContainer)
        self.modelContainer = modelContainer
        self.localPersistence = store

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
    }
}
