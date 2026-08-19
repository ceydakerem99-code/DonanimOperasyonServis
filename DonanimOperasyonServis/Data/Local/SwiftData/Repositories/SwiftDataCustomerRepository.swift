import Foundation

/// SwiftData-backed implementation of `CustomerRepository`.
struct SwiftDataCustomerRepository: CustomerRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func fetch(id: CustomerID) async throws -> Customer {
        guard let customer = try await store.fetchCustomer(id: id.rawValue) else {
            throw DomainError.notFound(entity: "Customer", id: id.rawValue)
        }
        return customer
    }

    func list(searchText: String?) async throws -> [Customer] {
        try await store.listCustomers(searchText: searchText)
    }

    func save(_ customer: Customer) async throws {
        try await store.upsertCustomer(customer)
    }

    func delete(id: CustomerID) async throws {
        try await store.deleteCustomer(id: id.rawValue)
    }
}
