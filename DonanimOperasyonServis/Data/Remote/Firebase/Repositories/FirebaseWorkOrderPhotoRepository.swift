import Foundation

/// Firestore-backed implementation of `WorkOrderPhotoRepository`.
/// Only metadata is stored in Firestore; image bytes belong to
/// Firebase Storage (see `FirebaseStoragePath`).
struct FirebaseWorkOrderPhotoRepository: WorkOrderPhotoRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderPhoto] {
        let dtos = try await dataSource.list(
            FirestoreWorkOrderPhotoDTO.self,
            collection: .workOrderPhotos,
            predicates: [.equal("workOrderId", .string(workOrderId.rawValue))],
            orderBy: [.ascending("capturedAt")]
        )
        return try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "WorkOrderPhoto") { $0.toDomain() }
        }
    }

    func save(_ photo: WorkOrderPhoto) async throws {
        try await dataSource.set(
            FirestoreWorkOrderPhotoDTO(domain: photo),
            collection: .workOrderPhotos,
            id: photo.id
        )
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        _ = workOrderId
        try await dataSource.delete(collection: .workOrderPhotos, id: id)
    }
}
