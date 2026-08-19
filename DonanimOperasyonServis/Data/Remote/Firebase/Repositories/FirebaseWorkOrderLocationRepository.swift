import Foundation

/// Firestore-backed implementation of `WorkOrderLocationRepository`.
struct FirebaseWorkOrderLocationRepository: WorkOrderLocationRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderLocation] {
        try await FirebaseRepositoryMapper.run(entity: "WorkOrderLocation", id: workOrderId.rawValue) {
            let dtos = try await dataSource.list(
                FirestoreWorkOrderLocationDTO.self,
                collection: .workOrderLocations,
                predicates: [.equal("workOrderId", .string(workOrderId.rawValue))],
                orderBy: [.ascending("capturedAt")]
            )
            return try dtos.map {
                try FirebaseRepositoryMapper.requireDomain($0, entity: "WorkOrderLocation") { $0.toDomain() }
            }
        }
    }

    func save(_ location: WorkOrderLocation) async throws {
        try await FirebaseRepositoryMapper.run(entity: "WorkOrderLocation", id: location.id) {
            try await dataSource.set(
                FirestoreWorkOrderLocationDTO(domain: location),
                collection: .workOrderLocations,
                id: location.id
            )
        }
    }
}
