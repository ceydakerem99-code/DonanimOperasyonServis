import Foundation

/// Persistence surface for `Customer` records.
protocol CustomerRepository: Sendable {
    func fetch(id: CustomerID) async throws -> Customer
    func list(searchText: String?) async throws -> [Customer]
    func save(_ customer: Customer) async throws
    func delete(id: CustomerID) async throws
}
