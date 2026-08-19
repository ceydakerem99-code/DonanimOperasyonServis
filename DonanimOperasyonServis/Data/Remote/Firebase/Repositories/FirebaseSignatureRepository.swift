import Foundation

/// Firestore-backed implementation of `SignatureRepository`.
/// Signature image bytes live in Firebase Storage; this repository
/// only persists metadata.
struct FirebaseSignatureRepository: SignatureRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func list(for workOrderId: WorkOrderID) async throws -> [Signature] {
        let dtos = try await dataSource.list(
            FirestoreSignatureDTO.self,
            collection: .signatures,
            predicates: [.equal("workOrderId", .string(workOrderId.rawValue))],
            orderBy: [.ascending("capturedAt")]
        )
        return try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "Signature") { $0.toDomain() }
        }
    }

    func save(_ signature: Signature) async throws {
        try await dataSource.set(
            FirestoreSignatureDTO(domain: signature),
            collection: .signatures,
            id: signature.id
        )
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        _ = workOrderId
        try await dataSource.delete(collection: .signatures, id: id)
    }
}
