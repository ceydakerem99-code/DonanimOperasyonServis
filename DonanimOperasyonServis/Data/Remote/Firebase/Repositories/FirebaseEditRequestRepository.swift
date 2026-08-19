import Foundation

/// Firestore-backed implementation of `EditRequestRepository`.
struct FirebaseEditRequestRepository: EditRequestRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func fetch(id: EditRequestID) async throws -> EditRequest {
        do {
            guard let dto = try await dataSource.fetch(
                FirestoreEditRequestDTO.self,
                collection: .editRequests,
                id: id.rawValue
            ) else {
                throw DomainError.notFound(entity: "EditRequest", id: id.rawValue)
            }
            return try FirebaseRepositoryMapper.requireDomain(dto, entity: "EditRequest") { $0.toDomain() }
        } catch {
            throw FirebaseRepositoryMapper.mapNotFound(error, entity: "EditRequest", id: id.rawValue)
        }
    }

    func list(for workOrderId: WorkOrderID) async throws -> [EditRequest] {
        let dtos = try await dataSource.list(
            FirestoreEditRequestDTO.self,
            collection: .editRequests,
            predicates: [.equal("workOrderId", .string(workOrderId.rawValue))],
            orderBy: [.ascending("createdAt")]
        )
        return try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "EditRequest") { $0.toDomain() }
        }
    }

    func listByStatus(_ status: EditRequestStatus) async throws -> [EditRequest] {
        let dtos = try await dataSource.list(
            FirestoreEditRequestDTO.self,
            collection: .editRequests,
            predicates: [.equal("status", .string(status.rawValue))],
            orderBy: [.ascending("createdAt")]
        )
        return try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "EditRequest") { $0.toDomain() }
        }
    }

    func save(_ request: EditRequest) async throws {
        try await dataSource.set(
            FirestoreEditRequestDTO(domain: request),
            collection: .editRequests,
            id: request.id.rawValue
        )
    }
}
