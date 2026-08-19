import Foundation

/// Persistence surface for `User` records. Implementations live in
/// the Data / Infrastructure layer (SwiftData local, Firestore
/// remote, or a coordinator over both). The Domain layer must not
/// import Firebase or SwiftData.
protocol UserRepository: Sendable {
    /// Fetches a single user by ID. Throws
    /// `DomainError.notFound(entity:id:)` if the user does not
    /// exist.
    func fetch(id: UserID) async throws -> User

    /// Convenience accessor for looking up a user by email. Returns
    /// `nil` when no such user exists (no error).
    func findByEmail(_ email: String) async throws -> User?

    /// Returns every user matching the filter. Pass `nil` values
    /// for filters that should not narrow the result set.
    func list(role: UserRole?, isActive: Bool?) async throws -> [User]

    /// Persists an insert or update. Implementations decide upsert
    /// semantics based on the entity's `id`.
    func save(_ user: User) async throws

    /// Removes the user permanently. In v1 this is admin-only —
    /// authorization is enforced at the use-case layer, not here.
    func delete(id: UserID) async throws
}
