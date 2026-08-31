import Foundation

/// Persistence surface for `Customer` records.
protocol CustomerRepository: Sendable {
    func fetch(id: CustomerID) async throws -> Customer
    func list(searchText: String?) async throws -> [Customer]
    func save(_ customer: Customer) async throws
    func delete(id: CustomerID) async throws
}

/// Shared in-memory customer search for local and remote list queries.
enum CustomerSearchFilter {
    static func apply(_ customers: [Customer], searchText: String?) -> [Customer] {
        guard let raw = searchText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !raw.isEmpty
        else {
            return customers
        }
        return customers.filter { matches($0, query: raw) }
    }

    static func matches(_ customer: Customer, query: String) -> Bool {
        let fields: [String?] = [
            customer.name,
            customer.contactPersonName,
            customer.email,
            customer.address,
            customer.city,
            customer.phoneNumber?.rawValue,
            customer.notes
        ]
        return fields.compactMap { $0?.lowercased() }.contains { $0.contains(query) }
    }
}
