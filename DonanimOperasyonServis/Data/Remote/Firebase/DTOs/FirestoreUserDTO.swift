import Foundation

/// Firestore DTO for the `users` collection. Pure `Codable`; no
/// Firebase imports so the type stays serialisable to plain JSON in
/// tests and remains framework-agnostic within the Data layer.
///
/// `Date` fields are stored as `Date`. When encoded through the
/// Firestore SDK's Codable pipeline they are written as native
/// Firestore `Timestamp` values (see live data source); when encoded
/// through the test fake's JSON pipeline they are written as
/// milliseconds since 1970. Both preserve full round-trip fidelity.
struct FirestoreUserDTO: Codable, Hashable, Sendable {
    let id: String
    let email: String
    let fullName: String
    /// Persisted as `UserRole.rawValue`.
    let role: String
    let phoneNumber: String?
    let isActive: Bool
    /// Optional map of preference key → enabled. Missing = all on.
    let notificationPreferences: [String: Bool]?
    let createdAt: Date
    let updatedAt: Date
}

extension FirestoreUserDTO {

    init(domain: User) {
        self.id = domain.id.rawValue
        self.email = domain.email
        self.fullName = domain.fullName
        self.role = domain.role.rawValue
        self.phoneNumber = domain.phoneNumber?.rawValue
        self.isActive = domain.isActive
        self.notificationPreferences = domain.notificationPreferences.enabledByKey.isEmpty
            ? nil
            : domain.notificationPreferences.enabledByKey
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
    }

    /// Reconstructs the Domain `User`. Returns `nil` if the
    /// persisted `role` string does not match a known
    /// `UserRole` — treated as `.invalidDocument` at the repository.
    func toDomain() -> User? {
        guard let role = UserRole(rawValue: role) else { return nil }
        return User(
            id: UserID(id),
            email: email,
            fullName: fullName,
            role: role,
            phoneNumber: phoneNumber.map(PhoneNumber.init),
            isActive: isActive,
            notificationPreferences: NotificationPreferences(
                enabledByKey: notificationPreferences ?? [:]
            ),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Partial `users/{uid}` write allowed by self-service Firestore rules.
struct FirestoreUserSelfServicePatchDTO: Encodable, Sendable {
    let notificationPreferences: [String: Bool]?
    let updatedAt: Date

    init(domain: User) {
        let prefs = domain.notificationPreferences.enabledByKey
        self.notificationPreferences = prefs.isEmpty ? nil : prefs
        self.updatedAt = domain.updatedAt
    }
}
