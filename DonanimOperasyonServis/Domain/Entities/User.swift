import Foundation

/// An authenticated user of the system. Roles are strictly one of
/// the three cases in `UserRole` (`admin`, `operator`, `technician`);
/// dynamic roles are not supported.
struct User: Hashable, Sendable, Identifiable, Codable {
    let id: UserID
    var email: String
    var fullName: String
    var role: UserRole
    var phoneNumber: PhoneNumber?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UserID,
        email: String,
        fullName: String,
        role: UserRole,
        phoneNumber: PhoneNumber? = nil,
        isActive: Bool = true,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.role = role
        self.phoneNumber = phoneNumber
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
