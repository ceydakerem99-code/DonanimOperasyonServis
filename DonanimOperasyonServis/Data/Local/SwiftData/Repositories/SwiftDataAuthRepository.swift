import Foundation

/// SwiftData-backed local session manager that satisfies
/// `AuthRepository`.
///
/// Phase 3 stand-in for offline/tests. Password verification is not
/// performed here — use `FakeAuthRepository` or
/// `FirebaseAuthRepository` for real authentication flows.
struct SwiftDataAuthRepository: AuthRepository {

    let store: LocalPersistence
    let clock: @Sendable () -> Date

    init(
        store: LocalPersistence,
        clock: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.clock = clock
    }

    func restoreSession(now: Date) async throws -> User? {
        try await currentUser()
    }

    func currentUser() async throws -> User? {
        guard let userId = try await store.currentSessionUserId() else {
            return nil
        }
        return try await store.fetchUser(id: userId)
    }

    func refreshCurrentUser(now: Date) async throws -> User? {
        try await currentUser()
    }

    func signIn(email: String, password: String) async throws -> User {
        _ = password
        guard let user = try await store.findUserByEmail(email) else {
            throw DomainError.notFound(entity: "User", id: email)
        }
        try await store.setCurrentSessionUserId(user.id.rawValue, at: clock())
        return user
    }

    func signOut() async throws {
        try await store.setCurrentSessionUserId(nil, at: clock())
    }

    func authStateChanges() async -> AsyncStream<AuthSessionEvent> {
        AsyncStream { $0.finish() }
    }
}
