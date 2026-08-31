import Foundation
import os

/// Test/preview `AuthRepository` that simulates Firebase Auth +
/// Firestore user lookup without touching the SDK.
///
/// When `store` and `localUsers` are supplied (mock DI), session
/// metadata is persisted through `LocalSessionModel` exactly like
/// production. Passwords stay in-memory only.
final class FakeAuthRepository: AuthRepository, @unchecked Sendable {

    private struct State {
        var currentUID: String?
        var usersByID: [String: User] = [:]
        var passwordByEmail: [String: String] = [:]
        var continuations: [UUID: AsyncStream<AuthSessionEvent>.Continuation] = [:]
        var signInError: DomainError?
        var restoreError: DomainError?
        var missingProfileUIDs: Set<String> = []
        var networkFailure = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let store: LocalPersistence?
    private let localUsers: (any UserRepository)?
    private let clock: @Sendable () -> Date

    init(
        store: LocalPersistence? = nil,
        localUsers: (any UserRepository)? = nil,
        clock: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.localUsers = localUsers
        self.clock = clock
    }

    func setNetworkFailure(_ enabled: Bool) {
        lock.withLock { $0.networkFailure = enabled }
    }

    func setMissingProfile(uid: String) {
        lock.withLock { $0.missingProfileUIDs.insert(uid) }
    }

    func seed(user: User, password: String) {
        lock.withLock {
            $0.usersByID[user.id.rawValue] = user
            $0.passwordByEmail[user.email.lowercased()] = password
        }
    }

    func updateUser(_ user: User) {
        lock.withLock { $0.usersByID[user.id.rawValue] = user }
    }

    func simulateExternalSignIn(user: User) async throws {
        lock.withLock { state in
            state.currentUID = user.id.rawValue
            state.usersByID[user.id.rawValue] = user
        }
        try await persistSession(user: user)
        emit(.signedIn(user.id))
    }

    func simulateExternalSignOut() async throws {
        lock.withLock { $0.currentUID = nil }
        try await clearPersistedSession(at: clock())
        emit(.signedOut)
    }

    func restoreSession(now: Date) async throws -> User? {
        let flags = lock.withLock { state -> (Bool, DomainError?, String?) in
            (state.networkFailure, state.restoreError, state.currentUID)
        }
        if flags.0 {
            throw DomainError.authenticationFailed(.networkUnavailable)
        }
        if let restoreError = flags.1 { throw restoreError }

        var uid = flags.2
        if uid == nil, let stored = try await store?.currentSessionUserId() {
            uid = stored
            lock.withLock { $0.currentUID = stored }
        }
        guard let uid else { return nil }
        return try await resolveProfile(uid: uid, now: now)
    }

    func currentUser() async throws -> User? {
        let uid = lock.withLock { $0.currentUID }
        if let uid, let user = lock.withLock({ $0.usersByID[uid] }) {
            return user
        }
        guard let userId = try await store?.currentSessionUserId() else {
            return nil
        }
        return try await localUsers?.fetch(id: UserID(userId))
    }

    func refreshCurrentUser(now: Date) async throws -> User? {
        guard let uid = lock.withLock({ $0.currentUID }) else { return nil }
        return try await resolveProfile(uid: uid, now: now)
    }

    func signIn(email: String, password: String) async throws -> User {
        let snapshot = lock.withLock { state -> (Bool, DomainError?, String, String) in
            (
                state.networkFailure,
                state.signInError,
                email.lowercased(),
                password
            )
        }
        if snapshot.0 {
            throw DomainError.authenticationFailed(.networkUnavailable)
        }
        if let signInError = snapshot.1 { throw signInError }

        let normalized = snapshot.2
        let password = snapshot.3
        let expected = lock.withLock { $0.passwordByEmail[normalized] }
        guard let expected else {
            throw DomainError.authenticationFailed(.invalidCredentials)
        }
        guard password == expected else {
            throw DomainError.authenticationFailed(.invalidCredentials)
        }

        guard let user = lock.withLock({ state in
            state.usersByID.values.first(where: { $0.email.lowercased() == normalized })
        }) else {
            throw DomainError.authenticationFailed(.userNotFound)
        }

        if lock.withLock({ $0.missingProfileUIDs.contains(user.id.rawValue) }) {
            throw DomainError.authenticationFailed(.userDocumentMissing)
        }

        guard user.isActive else {
            throw DomainError.authenticationFailed(.unauthorized)
        }

        lock.withLock { $0.currentUID = user.id.rawValue }
        try await persistSession(user: user, at: clock())
        emit(.signedIn(user.id))
        return user
    }

    func signOut() async throws {
        lock.withLock { $0.currentUID = nil }
        try await clearPersistedSession(at: clock())
        emit(.signedOut)
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        if lock.withLock({ $0.networkFailure }) {
            throw DomainError.authenticationFailed(.networkUnavailable)
        }
        guard let uid = lock.withLock({ $0.currentUID }) else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
        guard let user = lock.withLock({ $0.usersByID[uid] }) else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
        let emailKey = user.email.lowercased()
        let expected = lock.withLock { $0.passwordByEmail[emailKey] }
        guard let expected, expected == currentPassword else {
            throw DomainError.authenticationFailed(.invalidCredentials)
        }
        guard newPassword.count >= PasswordPolicy.minimumLength else {
            throw DomainError.authenticationFailed(.weakPassword)
        }
        guard newPassword != currentPassword else {
            throw DomainError.authenticationFailed(.sameAsCurrentPassword)
        }
        lock.withLock { $0.passwordByEmail[emailKey] = newPassword }
    }

    func authStateChanges() async -> AsyncStream<AuthSessionEvent> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { state in
                state.continuations[id] = continuation
                if let uid = state.currentUID {
                    continuation.yield(.signedIn(UserID(uid)))
                } else {
                    continuation.yield(.signedOut)
                }
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { $0.continuations[id] = nil }
            }
        }
    }

    private func resolveProfile(uid: String, now: Date) async throws -> User {
        if lock.withLock({ $0.missingProfileUIDs.contains(uid) }) {
            lock.withLock { $0.currentUID = nil }
            try await clearPersistedSession(at: now)
            throw DomainError.authenticationFailed(.userDocumentMissing)
        }
        guard let user = lock.withLock({ $0.usersByID[uid] }) else {
            lock.withLock { $0.currentUID = nil }
            try await clearPersistedSession(at: now)
            throw DomainError.authenticationFailed(.userDocumentMissing)
        }
        guard user.isActive else {
            lock.withLock { $0.currentUID = nil }
            try await clearPersistedSession(at: now)
            throw DomainError.authenticationFailed(.unauthorized)
        }
        try await persistSession(user: user, at: now)
        return user
    }

    private func persistSession(user: User, at timestamp: Date? = nil) async throws {
        let at = timestamp ?? clock()
        try await localUsers?.save(user)
        try await store?.setCurrentSessionUserId(user.id.rawValue, at: at)
    }

    private func clearPersistedSession(at timestamp: Date? = nil) async throws {
        try await store?.setCurrentSessionUserId(nil, at: timestamp ?? clock())
    }

    private func emit(_ event: AuthSessionEvent) {
        let continuations = lock.withLock { Array($0.continuations.values) }
        for continuation in continuations {
            continuation.yield(event)
        }
    }
}
