import Foundation
import SwiftData

/// SwiftData persistence model for `Customer`.
@Model
final class CustomerModel {

    @Attribute(.unique) var id: String

    var name: String
    var contactPersonName: String?
    var phoneNumberRaw: String?
    var email: String?
    var address: String
    var city: String?
    var notes: String?
    var createdByUserId: String

    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        contactPersonName: String?,
        phoneNumberRaw: String?,
        email: String?,
        address: String,
        city: String?,
        notes: String?,
        createdByUserId: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.contactPersonName = contactPersonName
        self.phoneNumberRaw = phoneNumberRaw
        self.email = email
        self.address = address
        self.city = city
        self.notes = notes
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Domain ↔ Model mapping

extension CustomerModel {

    convenience init(domain: Customer) {
        self.init(
            id: domain.id.rawValue,
            name: domain.name,
            contactPersonName: domain.contactPersonName,
            phoneNumberRaw: domain.phoneNumber?.rawValue,
            email: domain.email,
            address: domain.address,
            city: domain.city,
            notes: domain.notes,
            createdByUserId: domain.createdByUserId.rawValue,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    func apply(domain: Customer) {
        self.name = domain.name
        self.contactPersonName = domain.contactPersonName
        self.phoneNumberRaw = domain.phoneNumber?.rawValue
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
            phoneNumber: phoneNumberRaw.map(PhoneNumber.init),
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
