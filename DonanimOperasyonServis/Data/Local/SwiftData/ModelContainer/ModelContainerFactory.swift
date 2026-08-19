import Foundation
import SwiftData

/// Central factory for the app's SwiftData `ModelContainer`.
///
/// Exposes two well-known configurations:
///
/// - `live()` — disk-backed store, used by the running application
///   via `DIContainer.live()`.
/// - `inMemory()` — RAM-only store, used by previews and by every
///   unit test so tests never touch the user's simulator data or
///   pollute each other's state.
///
/// The schema is defined once (`Self.schema`) so every caller — the
/// production container, the in-memory container, and any future
/// migration tool — enumerates the same set of `@Model` types. Add
/// new persistence models here so they get registered with SwiftData.
enum ModelContainerFactory {

    /// The full list of SwiftData model types this app knows how to
    /// persist. Keep this in sync with the files under
    /// `Data/Local/SwiftData/Models/`.
    static let modelTypes: [any PersistentModel.Type] = [
        UserModel.self,
        CustomerModel.self,
        WorkOrderModel.self,
        WorkOrderNoteModel.self,
        WorkOrderStatusHistoryModel.self,
        WorkOrderPhotoModel.self,
        WorkOrderLocationModel.self,
        SignatureModel.self,
        EditRequestModel.self,
        NotificationModel.self,
        LocalSessionModel.self,
        SyncOperationModel.self,
        SyncConflictModel.self
    ]

    static var schema: Schema { Schema(modelTypes) }

    /// Disk-backed container. Used by the running application.
    /// Throws when SwiftData cannot open the store — the caller is
    /// expected to surface this to the user (or crash on cold start,
    /// per the DI wiring) since there is no meaningful fallback.
    static func live() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// In-memory container. Used by previews and unit tests. The
    /// underlying store lives only as long as the returned container
    /// instance, so each test gets a clean slate.
    static func inMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
