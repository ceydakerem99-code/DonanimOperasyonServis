import Foundation

/// Creates a customer for the operator surface.
struct CreateCustomerUseCase: Sendable {
    let customerRepository: CustomerRepository

    init(customerRepository: CustomerRepository) {
        self.customerRepository = customerRepository
    }

    func execute(
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
        guard RoleAccessPolicy.can(.createCustomer, as: actor.role) else {
            throw DomainError.unauthorized(action: .createCustomer)
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainError.invalidData(reason: "customer.nameEmpty")
        }
        guard !trimmedAddress.isEmpty else {
            throw DomainError.invalidData(reason: "customer.addressEmpty")
        }

        let customer = Customer(
            id: CustomerID(UUID().uuidString),
            name: trimmedName,
            contactPersonName: contactPersonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            phoneNumber: phoneNumber,
            email: email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            address: trimmedAddress,
            city: city?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdByUserId: actor.id,
            createdAt: now,
            updatedAt: now
        )
        try await customerRepository.save(customer)
        return customer
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
