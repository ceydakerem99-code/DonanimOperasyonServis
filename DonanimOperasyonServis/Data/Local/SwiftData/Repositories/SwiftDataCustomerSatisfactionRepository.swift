import Foundation

/// SwiftData-backed implementation of `CustomerSatisfactionRepository`.
struct SwiftDataCustomerSatisfactionRepository: CustomerSatisfactionRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func fetch(id: CustomerSatisfactionID) async throws -> CustomerSatisfaction {
        guard let satisfaction = try await store.fetchCustomerSatisfaction(id: id.rawValue) else {
            throw DomainError.notFound(entity: "CustomerSatisfaction", id: id.rawValue)
        }
        return satisfaction
    }

    func list(for workOrderId: WorkOrderID) async throws -> [CustomerSatisfaction] {
        try await store.listCustomerSatisfactions(workOrderId: workOrderId.rawValue)
    }

    func listByCustomer(_ customerId: CustomerID) async throws -> [CustomerSatisfaction] {
        try await store.listCustomerSatisfactions(customerId: customerId.rawValue)
    }

    func listByStatus(_ status: CustomerSatisfactionStatus) async throws -> [CustomerSatisfaction] {
        try await store.listCustomerSatisfactions(statusRaw: status.rawValue)
    }

    func save(_ satisfaction: CustomerSatisfaction) async throws {
        try await store.upsertCustomerSatisfaction(satisfaction)
    }
}
