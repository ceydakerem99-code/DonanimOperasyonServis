import Foundation

/// SwiftData-backed local session manager that satisfies
/// `AuthRepository`.
///
/// This is a **v3 stand-in** for the eventual Firebase Auth
/// implementation:
///
/// - `currentUser()` reads the `LocalSessionModel` row and joins it
///   back to a `UserModel`.
/// - `signIn(email:password:)` looks the user up by email in the
///   local store and marks them as the current session. The
///   `password` argument is accepted for API stability but is not
///   verified here — password verification will move to Firebase
///   Authentication in a later phase, and this repository will then
///   be replaced by a Firebase-backed implementation. Callers that
///   rely on real authentication must not use this repository
///   outside of tests and offline scenarios.
/// - `signOut()` clears the session pointer without touching any
///   cached user rows.
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

    func currentUser() async throws -> User? {
        guard let userId = try await store.currentSessionUserId() else {
            return nil
        }
        // The referenced user row may have been deleted; treat that as
        // "no current user" rather than a hard error so a stale
        // session does not brick the app.
        return try await store.fetchUser(id: userId)
    }

    func signIn(email: String, password: String) async throws -> User {
        _ = password  // See type docs: password is a Firebase concern.
        guard let user = try await store.findUserByEmail(email) else {
            throw DomainError.notFound(entity: "User", id: email)
        }
        try await store.setCurrentSessionUserId(user.id.rawValue, at: clock())
        return user
    }

    func signOut() async throws {
        try await store.setCurrentSessionUserId(nil, at: clock())
    }
}
