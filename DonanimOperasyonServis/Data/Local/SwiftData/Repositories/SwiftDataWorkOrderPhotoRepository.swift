import Foundation

/// SwiftData-backed implementation of `WorkOrderPhotoRepository`.
struct SwiftDataWorkOrderPhotoRepository: WorkOrderPhotoRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderPhoto] {
        try await store.listPhotos(workOrderId: workOrderId.rawValue)
    }

    func save(_ photo: WorkOrderPhoto) async throws {
        try await store.upsertPhoto(photo)
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        _ = workOrderId
        try await store.deletePhoto(id: id)
    }
}
