import Foundation

/// A customer served by the operations team. Customers are created by
/// operators and referenced by work orders.
struct Customer: Hashable, Sendable, Identifiable, Codable {
    let id: CustomerID
    var name: String
    var contactPersonName: String?
    var phoneNumber: PhoneNumber?
    var email: String?
    var address: String
    var city: String?
    var notes: String?
    var createdByUserId: UserID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: CustomerID,
        name: String,
        contactPersonName: String? = nil,
        phoneNumber: PhoneNumber? = nil,
        email: String? = nil,
        address: String,
        city: String? = nil,
        notes: String? = nil,
        createdByUserId: UserID,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.contactPersonName = contactPersonName
        self.phoneNumber = phoneNumber
        self.email = email
        self.address = address
        self.city = city
        self.notes = notes
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
