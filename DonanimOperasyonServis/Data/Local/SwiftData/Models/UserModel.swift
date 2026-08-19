import Foundation
import SwiftData

/// SwiftData persistence model for `User`. Kept in the Data layer so
/// the Domain `User` struct stays framework-agnostic.
///
/// Enum values are persisted as their raw `String` form to make the
/// storage layer forgiving to future schema additions (unknown
/// values would surface as decoding failures at the mapper rather
/// than crashing the store).
@Model
final class UserModel {

    @Attribute(.unique) var id: String

    var email: String
    var fullName: String
    /// Persisted as `UserRole.rawValue`.
    var roleRaw: String
    var phoneNumberRaw: String?
    var isActive: Bool

    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        email: String,
        fullName: String,
        roleRaw: String,
        phoneNumberRaw: String?,
        isActive: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.roleRaw = roleRaw
        self.phoneNumberRaw = phoneNumberRaw
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Domain ↔ Model mapping

extension UserModel {

    convenience init(domain: User) {
        self.init(
            id: domain.id.rawValue,
            email: domain.email,
            fullName: domain.fullName,
            roleRaw: domain.role.rawValue,
            phoneNumberRaw: domain.phoneNumber?.rawValue,
            isActive: domain.isActive,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    /// Overwrites mutable fields from `domain` while keeping the same
    /// persistent object identity. Used for upserts so relationships
    /// pointing at this row survive the update.
    func apply(domain: User) {
        self.email = domain.email
        self.fullName = domain.fullName
        self.roleRaw = domain.role.rawValue
        self.phoneNumberRaw = domain.phoneNumber?.rawValue
        self.isActive = domain.isActive
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
    }

    /// Reconstructs the Domain value. If the persisted `roleRaw`
    /// cannot be decoded the row is treated as corrupted and the
    /// call returns `nil`; callers should filter those out or throw
    /// `DomainError.invalidData` as appropriate.
    func toDomain() -> User? {
        guard let role = UserRole(rawValue: roleRaw) else { return nil }
        return User(
            id: UserID(id),
            email: email,
            fullName: fullName,
            role: role,
            phoneNumber: phoneNumberRaw.map(PhoneNumber.init),
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
