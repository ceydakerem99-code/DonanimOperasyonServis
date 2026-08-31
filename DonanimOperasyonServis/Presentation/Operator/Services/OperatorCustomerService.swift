import Foundation

/// Operator customer mutations with offline-first sync enqueue.
/// FAZ 3A also submits customer create to the WebSocket gateway (ACK required
/// when connected). SyncQueue enqueue is unchanged.
struct OperatorCustomerService: Sendable {
    let createCustomer: CreateCustomerUseCase
    let updateCustomer: UpdateCustomerUseCase
    let syncOperationRepository: SyncOperationRepository
    let realtimeCustomerCreate: (any RealtimeCustomerCreateSubmitting)?

    init(
        createCustomer: CreateCustomerUseCase,
        updateCustomer: UpdateCustomerUseCase,
        syncOperationRepository: SyncOperationRepository,
        realtimeCustomerCreate: (any RealtimeCustomerCreateSubmitting)? = nil
    ) {
        self.createCustomer = createCustomer
        self.updateCustomer = updateCustomer
        self.syncOperationRepository = syncOperationRepository
        self.realtimeCustomerCreate = realtimeCustomerCreate
    }

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
            localVersion: 1,
            actorUserId: actor.id.rawValue
        )
        _ = try await syncOperationRepository.enqueue(operation)
        if let realtimeCustomerCreate {
            _ = await realtimeCustomerCreate.submitCustomerCreate(
                customer,
                actorUserId: actor.id.rawValue
            )
        }
        return customer
    }

    @discardableResult
    func updateWithSync(
        actor: User,
        customerId: CustomerID,
        name: String,
        contactPersonName: String? = nil,
        phoneNumber: PhoneNumber? = nil,
        email: String? = nil,
        address: String,
        city: String? = nil,
        notes: String? = nil,
        at now: Date = Date()
    ) async throws -> Customer {
        let customer = try await updateCustomer.execute(
            actor: actor,
            customerId: customerId,
            name: name,
            contactPersonName: contactPersonName,
            phoneNumber: phoneNumber,
            email: email,
            address: address,
            city: city,
            notes: notes,
            at: now
        )
        try await AdminSyncEnqueue.enqueueUpdate(
            entityType: .customer,
            entityId: customer.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return customer
    }
}
