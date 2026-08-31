import Foundation

/// Firestore-backed implementation of `CustomerRepository`.
struct FirebaseCustomerRepository: CustomerRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func fetch(id: CustomerID) async throws -> Customer {
        try await FirebaseRepositoryMapper.run(entity: "Customer", id: id.rawValue) {
            guard let dto = try await dataSource.fetch(
                FirestoreCustomerDTO.self,
                collection: .customers,
                id: id.rawValue
            ) else {
                throw DomainError.notFound(entity: "Customer", id: id.rawValue)
            }
            return dto.toDomain()
        }
    }

    func list(searchText: String?) async throws -> [Customer] {
        try await FirebaseRepositoryMapper.run(entity: "Customer") {
            let dtos = try await dataSource.list(
                FirestoreCustomerDTO.self,
                collection: .customers,
                predicates: [],
                orderBy: [.ascending("name")]
            )
            let all = dtos.map { $0.toDomain() }
            return CustomerSearchFilter.apply(all, searchText: searchText)
        }
    }

    func save(_ customer: Customer) async throws {
        try await FirebaseRepositoryMapper.run(entity: "Customer", id: customer.id.rawValue) {
            try await dataSource.set(
                FirestoreCustomerDTO(domain: customer),
                collection: .customers,
                id: customer.id.rawValue
            )
        }
    }

    func delete(id: CustomerID) async throws {
        try await FirebaseRepositoryMapper.run(entity: "Customer", id: id.rawValue) {
            try await dataSource.delete(collection: .customers, id: id.rawValue)
        }
    }
}
