import Foundation

/// Firestore DTO for the `customers` collection.
struct FirestoreCustomerDTO: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let contactPersonName: String?
    let phoneNumber: String?
    let email: String?
    let address: String
    let city: String?
    let notes: String?
    let createdByUserId: String
    let createdAt: Date
    let updatedAt: Date
}

extension FirestoreCustomerDTO {

    init(domain: Customer) {
        self.id = domain.id.rawValue
        self.name = domain.name
        self.contactPersonName = domain.contactPersonName
        self.phoneNumber = domain.phoneNumber?.rawValue
        self.email = domain.email
        self.address = domain.address
        self.city = domain.city
        self.notes = domain.notes
        self.createdByUserId = domain.createdByUserId.rawValue
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
    }

    func toDomain() -> Customer {
        Customer(
            id: CustomerID(id),
            name: name,
            contactPersonName: contactPersonName,
            phoneNumber: phoneNumber.map(PhoneNumber.init),
            email: email,
            address: address,
            city: city,
            notes: notes,
            createdByUserId: UserID(createdByUserId),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
