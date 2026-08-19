import Foundation

/// Firestore-backed implementation of `CustomerRepository`.
struct FirebaseCustomerRepository: CustomerRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func fetch(id: CustomerID) async throws -> Customer {
        do {
            guard let dto = try await dataSource.fetch(
                FirestoreCustomerDTO.self,
                collection: .customers,
                id: id.rawValue
            ) else {
                throw DomainError.notFound(entity: "Customer", id: id.rawValue)
            }
            return dto.toDomain()
        } catch {
            throw FirebaseRepositoryMapper.mapNotFound(error, entity: "Customer", id: id.rawValue)
        }
    }

    func list(searchText: String?) async throws -> [Customer] {
        let dtos = try await dataSource.list(
            FirestoreCustomerDTO.self,
            collection: .customers,
            predicates: [],
            orderBy: [.ascending("name")]
        )
        let all = dtos.map { $0.toDomain() }
        guard let raw = searchText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !raw.isEmpty
        else {
            return all
        }
        // Firestore has no native "contains, case-insensitive"
        // operator. Name search is applied in memory after a
        // collection-wide fetch — acceptable at v4 scale, and the
        // same strategy the SwiftData repository already uses.
        return all.filter { $0.name.lowercased().contains(raw) }
    }

    func save(_ customer: Customer) async throws {
        try await dataSource.set(
            FirestoreCustomerDTO(domain: customer),
            collection: .customers,
            id: customer.id.rawValue
        )
    }

    func delete(id: CustomerID) async throws {
        try await dataSource.delete(collection: .customers, id: id.rawValue)
    }
}
