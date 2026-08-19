import Foundation

/// Authentication surface. This is a Domain-level protocol; the
/// Firebase-backed implementation lives in the Infrastructure layer
/// (added in a later phase).
///
/// `currentUser()` returns the authenticated user's profile in
/// `User` form (i.e. mapped from the auth provider's user record
/// via `UserRepository`). It returns `nil` when no session is
/// active.
protocol AuthRepository: Sendable {
    func currentUser() async throws -> User?
    func signIn(email: String, password: String) async throws -> User
    func signOut() async throws
}
