import Foundation

/// Firestore-backed implementation of `WorkOrderNoteRepository`.
struct FirebaseWorkOrderNoteRepository: WorkOrderNoteRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderNote] {
        try await FirebaseRepositoryMapper.run(entity: "WorkOrderNote", id: workOrderId.rawValue) {
            let dtos = try await dataSource.list(
                FirestoreWorkOrderNoteDTO.self,
                collection: .workOrderNotes,
                predicates: [.equal("workOrderId", .string(workOrderId.rawValue))],
                orderBy: [.ascending("createdAt")]
            )
            return dtos.map { $0.toDomain() }
        }
    }

    func save(_ note: WorkOrderNote) async throws {
        try await FirebaseRepositoryMapper.run(entity: "WorkOrderNote", id: note.id) {
            try await dataSource.set(
                FirestoreWorkOrderNoteDTO(domain: note),
                collection: .workOrderNotes,
                id: note.id
            )
        }
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        _ = workOrderId
        try await FirebaseRepositoryMapper.run(entity: "WorkOrderNote", id: id) {
            try await dataSource.delete(collection: .workOrderNotes, id: id)
        }
    }
}
