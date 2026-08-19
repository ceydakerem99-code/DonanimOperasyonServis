import Foundation

/// Firestore-backed implementation of
/// `WorkOrderStatusHistoryRepository`. History entries are
/// append-only from the Domain's perspective; Firestore stores
/// each entry as its own document keyed by `id`.
struct FirebaseWorkOrderStatusHistoryRepository: WorkOrderStatusHistoryRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderStatusHistory] {
        let dtos = try await dataSource.list(
            FirestoreWorkOrderStatusHistoryDTO.self,
            collection: .workOrderStatusHistory,
            predicates: [.equal("workOrderId", .string(workOrderId.rawValue))],
            orderBy: [.ascending("occurredAt")]
        )
        return try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "WorkOrderStatusHistory") { $0.toDomain() }
        }
    }

    func append(_ entry: WorkOrderStatusHistory) async throws {
        try await dataSource.set(
            FirestoreWorkOrderStatusHistoryDTO(domain: entry),
            collection: .workOrderStatusHistory,
            id: entry.id
        )
    }
}
