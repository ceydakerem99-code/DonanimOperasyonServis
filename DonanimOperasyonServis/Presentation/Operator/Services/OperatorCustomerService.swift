import Foundation

/// Operator customer mutations with offline-first sync enqueue.
struct OperatorCustomerService: Sendable {
    let createCustomer: CreateCustomerUseCase
    let syncOperationRepository: SyncOperationRepository

    @discardableResult
    func createWithSync(
        actor: User,
        name: String,
        contactPersonName: String? = nil,
        phoneNumber: PhoneNumber? = nil,
        email: String? = nil,
        address: String,
        city: String? = nil,
        notes: String? = nil,
        at now: Date = Date()
    ) async throws -> Customer {
        let customer = try await createCustomer.execute(
            actor: actor,
            name: name,
            contactPersonName: contactPersonName,
            phoneNumber: phoneNumber,
            email: email,
            address: address,
            city: city,
            notes: notes,
            at: now
        )
        let operation = try SyncOperation.pending(
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await syncOperationRepository.enqueue(operation)
        return customer
    }
}
