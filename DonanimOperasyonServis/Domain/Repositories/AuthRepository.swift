import Foundation

/// Authentication surface. Domain never imports Firebase Auth.
/// Implementations live in Data (`FirebaseAuthRepository`,
/// `FakeAuthRepository`, `SwiftDataAuthRepository`).
protocol AuthRepository: Sendable {
    /// Probes Firebase (or fake) session on launch, loads
    /// `users/{uid}` when needed, caches locally, and updates
    /// `LocalSessionModel`. Returns `nil` when unauthenticated.
    func restoreSession(now: Date) async throws -> User?

    /// Returns the cached domain user for the active session, or
    /// `nil` when no session pointer exists.
    func currentUser() async throws -> User?

    /// Re-fetches `users/{uid}` from remote so role / profile
    /// changes are visible without forcing a new login.
    func refreshCurrentUser(now: Date) async throws -> User?

    func signIn(email: String, password: String) async throws -> User
    func signOut() async throws

    /// Observes provider session changes (login, logout, token
    /// expiry). The stream's first value reflects the current UID.
    func authStateChanges() async -> AsyncStream<AuthSessionEvent>
}

extension AuthRepository {
    func restoreSession() async throws -> User? {
        try await restoreSession(now: Date())
    }

    func refreshCurrentUser() async throws -> User? {
        try await refreshCurrentUser(now: Date())
    }
}
