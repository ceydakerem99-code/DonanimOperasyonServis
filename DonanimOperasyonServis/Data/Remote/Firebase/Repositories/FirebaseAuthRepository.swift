import Foundation

/// Firebase Authentication + Firestore `users/{uid}` profile join.
///
/// Flow:
/// 1. Firebase Auth establishes the provider session (UID).
/// 2. Firestore user document **must** exist at `users/{uid}`.
/// 3. Domain `User.id` == Firebase Auth UID (deterministic).
/// 4. Profile is cached in SwiftData; `LocalSessionModel` stores
///    the active user id pointer only (no password / token).
///
/// Logout clears provider + session pointer. Local business data and
/// the sync queue are intentionally untouched.
struct FirebaseAuthRepository: AuthRepository {

    let authService: any FirebaseAuthServing
    let remoteUsers: any UserRepository
    let localUsers: any UserRepository
    let store: LocalPersistence
    let clock: @Sendable () -> Date

    init(
        authService: any FirebaseAuthServing,
        remoteUsers: any UserRepository,
        localUsers: any UserRepository,
        store: LocalPersistence,
        clock: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.authService = authService
        self.remoteUsers = remoteUsers
        self.localUsers = localUsers
        self.store = store
        self.clock = clock
    }

    func restoreSession(now: Date) async throws -> User? {
        guard let uid = authService.currentUID else {
            try await clearSession(at: now)
            return nil
        }
        return try await loadAuthenticatedUser(uid: uid, now: now)
    }

    func currentUser() async throws -> User? {
        guard authService.currentUID != nil else {
            return nil
        }
        guard let userId = try await store.currentSessionUserId() else {
            return nil
        }
        return try await localUsers.fetch(id: UserID(userId))
    }

    func refreshCurrentUser(now: Date) async throws -> User? {
        guard let uid = authService.currentUID else {
            try await clearSession(at: now)
            return nil
        }
        return try await loadAuthenticatedUser(uid: uid, now: now)
    }

    func signIn(email: String, password: String) async throws -> User {
        do {
            let uid = try await authService.signIn(email: email, password: password)
            return try await loadAuthenticatedUser(uid: uid, now: clock())
        } catch {
            throw FirebaseAuthErrorMapper.map(error)
        }
    }

    func signOut() async throws {
        try await authService.signOut()
        try await clearSession(at: clock())
    }

    func authStateChanges() async -> AsyncStream<AuthSessionEvent> {
        let stream = authService.authStateChanges()
        return AsyncStream { continuation in
            Task {
                for await uid in stream {
                    if let uid {
                        continuation.yield(.signedIn(UserID(uid)))
                    } else {
                        continuation.yield(.signedOut)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Session helpers

    private func loadAuthenticatedUser(uid: String, now: Date) async throws -> User {
        let userID = UserID(uid)
        let user: User
        do {
            user = try await remoteUsers.fetch(id: userID)
        } catch let error as DomainError {
            if case .notFound = error {
                try? await authService.signOut()
                try await clearSession(at: now)
                throw DomainError.authenticationFailed(.userDocumentMissing)
            }
            throw error
        } catch {
            throw FirebaseAuthErrorMapper.map(error)
        }

        guard user.isActive else {
            try? await authService.signOut()
            try await clearSession(at: now)
            throw DomainError.authenticationFailed(.unauthorized)
        }

        try await localUsers.save(user)
        try await store.setCurrentSessionUserId(uid, at: now)
        return user
    }

    private func clearSession(at timestamp: Date) async throws {
        try await store.setCurrentSessionUserId(nil, at: timestamp)
    }
}
